defmodule ThistleTea.Game.Entity.Logic.ItemLoot do
  @moduledoc """
  Player-owned loot retained after an item is consumed. A claim plans its
  inventory placement and removes the loot slot together, so failed placement
  leaves the rewards intact. The owning player serializes all claims. The
  consumed item's snapshot supplies a client loot source without restoring
  inventory ownership or an ItemStore entry.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Loot

  @enforce_keys [:guid, :source, :loot]
  defstruct [:guid, :source, :loot]

  def new(%Item{} = item, %Loot{} = loot), do: %__MODULE__{guid: item.object.guid, source: item, loot: loot}

  def claim(
        %Character{internal: %{item_loot: %__MODULE__{loot: loot} = pending}} = character,
        slot,
        %Item{} = item,
        get_item
      ) do
    with {:ok, reward, remaining} <- Loot.commit_item(loot, slot),
         true <- reward.item_id == item.object.entry and reward.count == item.item.stack_count,
         true <- item.item.owner == character.object.guid,
         {:ok, changes} <- character.player |> Batch.new() |> Batch.add(item) |> Inventory.plan(get_item) do
      pending = if !Loot.empty?(remaining), do: %{pending | loot: remaining}
      character = %{character | internal: %{character.internal | item_loot: pending}}
      {:ok, character, changes}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :already_looted}
    end
  end

  def claim(_character, _slot, _item, _get_item), do: {:error, :already_looted}
end
