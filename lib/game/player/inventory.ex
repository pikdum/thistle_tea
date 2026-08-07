defmodule ThistleTea.Game.Player.Inventory do
  @moduledoc """
  Player-owner boundary for client-directed inventory transitions.

  Generic slot packets pass through this module so bank positions cannot be
  addressed without a currently valid banker session.
  """

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Bank
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World.ItemStore

  def swap(%State{} = state, source_position, destination_position) do
    case Bank.authorize_positions(state, [source_position, destination_position]) do
      {:ok, state} ->
        character = state.character

        Inventory.swap(
          character.player,
          character.unit,
          Proficiency.from_character(character),
          state.guid,
          source_position,
          destination_position,
          &ItemStore.get/1,
          validate_item: &Reputation.validate_item_requirement(character, &1)
        )
        |> then(&InventoryUpdate.apply(state, &1))

      {:error, state} ->
        reject_remote_bank(state)
    end
  end

  def split(%State{} = state, source_position, destination_position, count) when is_integer(count) and count > 0 do
    with {:ok, state} <- Bank.authorize_positions(state, [source_position, destination_position]),
         source_guid when is_integer(source_guid) <-
           Inventory.item_guid_at(state.character.player, source_position, &ItemStore.get/1),
         %Item{} = source_item <- ItemStore.get(source_guid),
         %Item{} = new_item <- ItemStore.create(Item.template(source_item), owner: state.guid, stack_count: count) do
      commit_split(state, source_position, destination_position, new_item)
    else
      {:error, state} -> reject_remote_bank(state)
      _missing -> reject_missing_item(state)
    end
  end

  def split(%State{} = state, _source_position, _destination_position, _count), do: state

  def destroy(%State{} = state, position) do
    case Bank.authorize_positions(state, [position]) do
      {:ok, state} ->
        case Inventory.destroy(state.character.player, position, &ItemStore.get/1) do
          {:ok, result, item} -> InventoryUpdate.apply(state, {:ok, %{result | destroyed: [item]}})
          error -> InventoryUpdate.apply(state, error)
        end

      {:error, state} ->
        reject_remote_bank(state)
    end
  end

  defp commit_split(state, source_position, destination_position, new_item) do
    case Inventory.split(
           state.character.player,
           state.guid,
           source_position,
           destination_position,
           new_item,
           &ItemStore.get/1
         ) do
      {:ok, result, placed} ->
        change_set =
          state.character.player
          |> ChangeSet.new()
          |> ChangeSet.absorb(result)
          |> ChangeSet.place(new_item, {:placed, destination_position, placed})

        InventoryUpdate.apply(state, {:ok, change_set})

      {:error, error, item1_guid, item2_guid} ->
        ItemStore.delete(new_item.object.guid)
        InventoryUpdate.send_failure(error, item1_guid, item2_guid)
        state
    end
  end

  defp reject_remote_bank(state) do
    InventoryUpdate.send_failure(:too_far_away_from_bank, 0, 0)
    state
  end

  defp reject_missing_item(state) do
    InventoryUpdate.send_failure(:item_not_found, 0, 0)
    state
  end
end
