defmodule ThistleTea.Game.Player.Durability do
  @moduledoc """
  Owner-local durability updates and nearby repair-vendor transactions.
  Every request revalidates the live vendor and the player's carried items.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Durability, as: DurabilityLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Durability, as: DurabilityLoader
  alias ThistleTea.Game.World.Metadata

  @repair_flag 0x00004000

  def lose(
        %{character: %Character{object: %{guid: guid}} = character} = state,
        %Effects.DurabilityLoss{target_guid: guid} = effect
      ) do
    case DurabilityLogic.loss(character.player, effect.mode, effect.amount, effect.scope, &ItemStore.get/1) do
      {:ok, %ChangeSet{}} = result ->
        state = commit(state, result)
        if effect.death?, do: Network.send_packet(%Message.SmsgDurabilityDamageDeath{})
        spell_log(state.character, effect)
        state

      {:error, _reason} ->
        state
    end
  end

  def lose(state, %Effects.DurabilityLoss{}), do: state

  def lose(%{character: %Character{} = character} = state, mode, amount, scope, death? \\ false) do
    lose(state, %Effects.DurabilityLoss{
      target_guid: character.object.guid,
      mode: mode,
      amount: amount,
      scope: scope,
      death?: death?
    })
  end

  def repair(%{ready: true, character: %Character{} = character} = state, vendor_guid, item_guid) do
    if valid_vendor?(character, vendor_guid) do
      discount = Reputation.price(character, vendor_guid, 100) / 100

      result =
        DurabilityLogic.repair(character.player, item_guid, &ItemStore.get/1, &DurabilityLoader.cost(&1, discount))

      commit(state, result)
    else
      state
    end
  end

  def repair(state, _vendor_guid, _item_guid), do: state

  def valid_vendor?(%Character{} = character, vendor_guid) do
    with true <- Death.alive?(character),
         :mob <- Guid.entity_type(vendor_guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(vendor_guid, [:alive?, :npc_flags]),
         true <- (flags &&& @repair_flag) != 0,
         true <- Reputation.can_interact?(character, vendor_guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(vendor_guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, vendor_guid) do
      true
    else
      _invalid -> false
    end
  end

  defp commit(state, {:ok, %ChangeSet{changed: changed}}) when map_size(changed) == 0, do: state
  defp commit(state, {:ok, %ChangeSet{}} = result), do: InventoryUpdate.apply(state, result)
  defp commit(state, {:error, _reason}), do: state

  defp spell_log(character, %Effects.DurabilityLoss{mode: :points, caster_guid: caster, spell_id: spell_id} = effect)
       when is_integer(caster) and is_integer(spell_id) do
    entry = DurabilityLogic.spell_log_entry(character.player, effect.scope, &ItemStore.get/1)

    if is_integer(entry) do
      %Message.SmsgSpelllogexecute{
        caster: caster,
        spell_id: spell_id,
        logs: [{:durability_damage, character.object.guid, entry}]
      }
      |> World.broadcast_packet(caster)
    end
  end

  defp spell_log(_character, _effect), do: :ok
end
