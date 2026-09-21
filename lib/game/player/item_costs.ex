defmodule ThistleTea.Game.Player.ItemCosts do
  @moduledoc """
  Applies completed spell item effects on their owning player. Trade preparation
  settles already queued costs before freezing the inventory snapshot.
  """
  import Kernel, except: [apply: 2]

  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Disenchant
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.Gathering
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World.ItemStore

  @commands [
    :consume_cast_item,
    :consume_reagents,
    :enchant_item,
    :enchant_item_permanent,
    :disenchant_item,
    :open_lock
  ]

  def settle(state) do
    receive do
      command when is_tuple(command) and elem(command, 0) in @commands -> state |> apply(command) |> settle()
    after
      0 -> state
    end
  end

  def apply(state, {:consume_cast_item, guid}), do: Items.consume_cast_item(state, guid)

  def apply(state, {:consume_reagents, reagents}) do
    batch =
      Enum.reduce(reagents, Batch.new(state.character.player), fn {entry, count}, batch ->
        Batch.remove(batch, entry, count)
      end)

    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} -> InventoryUpdate.apply(state, {:ok, changes})
      _ -> state
    end
  end

  def apply(state, {:enchant_item, guid, spell, enchantment_id, duration, cast_item_guid}) do
    Enchantments.apply_temporary(state, guid, spell, enchantment_id, duration, cast_item_guid)
  end

  def apply(state, {:enchant_item_permanent, guid, spell, enchantment_id, cast_item_guid}) do
    Enchantments.apply_permanent(state, guid, spell, enchantment_id, cast_item_guid)
  end

  def apply(state, {:disenchant_item, guid, spell_id}), do: Disenchant.complete(state, guid, spell_id)

  def apply(state, {:open_lock, guid, spell, cast_item_guid, success_events}),
    do: Gathering.complete(state, guid, spell, cast_item_guid, success_events)
end
