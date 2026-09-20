defmodule ThistleTea.Game.Player.Trade do
  @moduledoc """
  Player-owned trade validation, inventory freezing, and receipt projection.
  A committed receipt survives either participant or coordinator restarting.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Trade.Decision
  alias ThistleTea.Game.Entity.Data.Trade.Enchantment
  alias ThistleTea.Game.Entity.Data.Trade.Prepare
  alias ThistleTea.Game.Entity.Data.Trade.Receipt
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Trade, as: TradeLogic
  alias ThistleTea.Game.Entity.Logic.Trade.Enchantments, as: TradeEnchantments
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgTradeStatus
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment
  alias ThistleTea.Game.World.System.Trade, as: TradeSystem

  def request(%{ready: true, character: %Character{}} = state, action) do
    with :ok <- available(state),
         {:ok, action} <- validate_action(state, action),
         :ok <- TradeSystem.request(state.guid, action) do
      state
    else
      {:inventory, reason, guid} ->
        InventoryUpdate.send_failure(reason, guid, 0)
        state

      {:error, reason} ->
        Network.send_packet(%SmsgTradeStatus{status: reason})
        state
    end
  end

  def request(state, _action), do: state

  def enchant(%{ready: true, character: %Character{} = character} = state, spell, 6, cast_item_guid) do
    with {:ok, id, %Item{} = item, offer} <- TradeSystem.request(state.guid, :enchant_target),
         cast = enchantment(spell, item.object.guid, cast_item_guid),
         offer = %{offer | spell: cast},
         :ok <- TradeEnchantments.validate(character, offer, item, Time.now(), &ItemStore.get/1, &ItemEnchantment.get/1),
         {:ok, batch} <- TradeEnchantments.costs(Batch.new(character.player), character, offer, &ItemStore.get/1),
         {:ok, _changes} <- Inventory.plan(batch, &ItemStore.get/1),
         :ok <- TradeSystem.request(state.guid, {:enchant, id, cast}) do
      Network.send_packet(Message.SmsgCastResult.failure(spell.id, :dont_report))
      {:ok, state}
    else
      {:error, :item_not_found} -> cast_failure(state, spell, :reagents)
      {:error, reason} -> cast_failure(state, spell, reason)
      _ -> cast_failure(state, spell, :not_trading)
    end
  end

  def enchant(state, spell, _slot, _cast_item_guid), do: cast_failure(state, spell, :item_not_ready)

  defp enchantment(spell, target_guid, cast_item_guid) do
    effects =
      for effect <- spell.effects, effect.type in [:enchant_item, :enchant_item_temporary] do
        %{
          type: effect.type,
          id: effect.misc_value,
          duration_ms: ItemEnchantment.duration_ms(spell.id, effect),
          charges: ItemEnchantment.charges(spell.id),
          token: make_ref()
        }
      end

    %Enchantment{
      spell: spell,
      target_guid: target_guid,
      cast_item_guid: cast_item_guid,
      effects: effects,
      recipe: ItemEnchantment.recipe(spell.id),
      skill_roll: :rand.uniform(100) - 1
    }
  end

  defp cast_failure(state, spell, reason) do
    Network.send_packet(Message.SmsgCastResult.failure(spell.id, reason))
    {:error, state}
  end

  def prepare(state, %Prepare{id: id, coordinator: coordinator}) do
    monitor = Process.monitor(coordinator)

    try do
      with :ok <- available(state),
           _character = CharacterStore.put(state.character),
           :ok <- TradeSystem.prepared(coordinator, id, state.character, Quests.quest_item_counts(state.character)) do
        await(coordinator, id, state.guid, monitor)
      else
        _ -> TradeSystem.abort(coordinator, id, state.guid)
      end

      apply_receipt(state, id)
    catch
      :exit, {:noproc, _call} -> apply_receipt(state, id)
      :exit, {:normal, _call} -> apply_receipt(state, id)
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  def recover(%Character{} = character) do
    case ItemStore.pending_trade(character.object.guid) do
      %Receipt{} = receipt ->
        character = receipt_character(character, receipt)
        CharacterStore.put(character)
        character

      nil ->
        character
    end
  end

  def finish_recovery(state) do
    case ItemStore.pending_trade(state.guid) do
      %Receipt{} = receipt ->
        state = Quests.on_inventory_changed(state, receipt.old_counts)
        CharacterStore.put(state.character)
        ItemStore.acknowledge_trade(receipt)
        state

      nil ->
        state
    end
  end

  def available(%{ready: true, character: %Character{} = character, logout_timer: logout_timer}) do
    cond do
      not is_nil(logout_timer) -> {:error, :you_logout}
      not Death.alive?(character) -> {:error, :you_dead}
      Aura.has_aura?(character, :mod_stun) -> {:error, :you_stunned}
      not is_nil(character.internal.taxi_flight) -> {:error, :target_to_far}
      true -> :ok
    end
  end

  def available(_state), do: {:error, :trade_canceled}

  defp validate_action(state, {:money, amount}) do
    if amount <= state.character.player.coinage,
      do: {:ok, {:money, amount}},
      else: {:inventory, :not_enough_money, 0}
  end

  defp validate_action(state, {:item, slot, bag, inventory_slot}) do
    guid = Inventory.item_guid_at(state.character.player, {bag, inventory_slot}, &ItemStore.get/1)

    with %Item{} = item <- ItemStore.get(guid),
         :ok <-
           TradeLogic.validate_item(state.character, item, slot, Time.now(), &ItemStore.get/1, &ItemEnchantment.get/1) do
      {:ok, {:item, slot, item}}
    else
      {:error, reason} -> {:inventory, reason, guid || 0}
      _ -> {:inventory, :item_not_found, guid || 0}
    end
  end

  defp validate_action(_state, action), do: {:ok, action}

  defp await(coordinator, id, guid, monitor) do
    receive do
      %Decision{id: ^id} -> :ok
      {:DOWN, ^monitor, :process, ^coordinator, _reason} -> :ok
    after
      3_000 -> TradeSystem.abort(coordinator, id, guid)
    end
  end

  defp apply_receipt(state, id) do
    case ItemStore.pending_trade(state.guid) do
      %Receipt{id: ^id} = receipt ->
        state = %{state | character: receipt_character(state.character, receipt)}
        state = InventoryUpdate.apply_committed(state, receipt.changes, receipt.old_counts, receipt.outgoing)
        state = %{state | character: state.character |> Enchantments.restore() |> EventSink.emit_pending()}
        Enchantments.send_active_timers(state.character)
        project_enchantment(state.character, receipt.cast)
        CharacterStore.put(state.character)
        ItemStore.acknowledge_trade(receipt)
        Network.send_packet(%SmsgTradeStatus{status: :trade_complete})
        state

      _ ->
        state
    end
  end

  defp receipt_character(%Character{internal: %{last_trade_id: id}} = character, %Receipt{id: id}), do: character

  defp receipt_character(%Character{} = character, %Receipt{} = receipt) do
    character = %{
      character
      | player: receipt.changes.player,
        internal: %{character.internal | last_trade_id: receipt.id}
    }

    spend_enchantment(character, receipt.cast, receipt.committed_at)
  end

  defp spend_enchantment(character, nil, _now), do: character

  defp spend_enchantment(character, %Enchantment{spell: spell}, now) do
    character |> Resources.spend_power(spell, now) |> Cooldowns.start(spell, now)
  end

  defp project_enchantment(_character, nil), do: :ok

  defp project_enchantment(character, %Enchantment{} = cast) do
    Network.send_packet(%Message.SmsgCastResult{spell: cast.spell.id, result: 0})

    World.broadcast_packet(
      %Message.SmsgSpellGo{
        cast_item: cast.cast_item_guid || character.object.guid,
        caster: character.object.guid,
        spell: cast.spell.id,
        flags: 0,
        hits: [],
        misses: [],
        targets: Target.item(cast.target_guid)
      },
      character
    )
  end
end
