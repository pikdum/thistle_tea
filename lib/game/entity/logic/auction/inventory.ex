defmodule ThistleTea.Game.Entity.Logic.Auction.Inventory do
  @moduledoc """
  Plans auction fees and exact-item escrow through the shared inventory batch.
  Ordinary transfer rules also reject bound items, active cast ingredients,
  equipped bags, and bags containing items.
  """

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Entity.Data.Auction.Change
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Trade

  @conjured 0x2

  def validate_sale(%Character{} = character, %Item{} = item, now, get_item, get_enchantment) do
    with :ok <- Trade.validate_item(character, item, 0, now, get_item, get_enchantment) do
      cond do
        band(Item.template(item).flags, @conjured) != 0 -> {:error, :item_not_found}
        (item.item.duration || 0) != 0 -> {:error, :item_not_found}
        true -> :ok
      end
    end
  end

  def plan(%Character{} = character, %Change{cost: cost} = change, get_item) do
    if character.player.coinage >= cost do
      player = %{character.player | coinage: character.player.coinage - cost}

      player
      |> Batch.new()
      |> detach_sale(change)
      |> Inventory.plan(get_item)
    else
      {:error, :not_enough_money}
    end
  end

  defp detach_sale(batch, %Change{action: :started, auction: auction}) do
    Batch.relocate(batch, auction.item.object.guid, :detached)
  end

  defp detach_sale(batch, _change), do: batch
end
