defmodule ThistleTea.Game.Player.Gifts do
  @moduledoc """
  Owner-local gift wrapping with bank authorization and cached gift templates.
  Completed item costs settle before a new item identity can be installed.
  """
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.ItemWrapping
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Bank
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  def wrap(%{ready: true, active_mover_guid: mover, guid: owner} = state, paper_position, target_position)
      when mover in [nil, 0, owner] do
    state = ItemCosts.settle(state)

    case Bank.authorize_positions(state, [paper_position, target_position]) do
      {:ok, state} -> wrap_authorized(state, paper_position, target_position)
      {:error, state} -> failure(state, :too_far_away_from_bank, 0)
    end
  end

  def wrap(state, _paper_position, _target_position), do: state

  defp wrap_authorized(state, paper_position, target_position) do
    paper_guid = Inventory.item_guid_at(state.character.player, paper_position, &ItemStore.get/1)
    target_guid = Inventory.item_guid_at(state.character.player, target_position, &ItemStore.get/1)

    gift =
      case ItemStore.get(paper_guid) do
        %Item{} = paper -> ItemLoader.get_template(Item.template(paper).wrapped_gift)
        _ -> nil
      end

    case ItemWrapping.wrap(state.character, paper_position, target_position, gift, &ItemStore.get/1) do
      {:ok, changes} -> InventoryUpdate.apply(state, {:ok, changes})
      {:error, reason} -> failure(state, reason, target_guid || 0)
    end
  end

  defp failure(state, reason, guid) do
    InventoryUpdate.send_failure(reason, guid, 0)
    state
  end
end
