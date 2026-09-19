defmodule ThistleTea.Game.Player.Durability do
  @moduledoc """
  Owner-local durability updates and nearby repair-vendor transactions.
  Every request revalidates the live vendor and the player's carried items.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Durability, as: DurabilityLogic
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

  def lose(%{character: %Character{} = character} = state, mode, amount, scope, death? \\ false) do
    result = DurabilityLogic.loss(character.player, mode, amount, scope, &ItemStore.get/1)
    state = commit(state, result)
    if death?, do: Network.send_packet(%Message.SmsgDurabilityDamageDeath{})
    state
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
end
