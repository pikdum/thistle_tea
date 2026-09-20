defmodule ThistleTea.Game.Player.Trade do
  @moduledoc """
  Player-owned trade validation, inventory freezing, and receipt projection.
  A committed receipt survives either participant or coordinator restarting.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Trade.Decision
  alias ThistleTea.Game.Entity.Data.Trade.Prepare
  alias ThistleTea.Game.Entity.Data.Trade.Receipt
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Trade, as: TradeLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message.SmsgTradeStatus
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Time
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
    %{character | player: receipt.changes.player, internal: %{character.internal | last_trade_id: receipt.id}}
  end
end
