defmodule ThistleTea.Game.World.Entity.Player.Inventory do
  @moduledoc """
  Player-owner boundary for client-directed inventory transitions.

  Generic slot packets pass through this module so bank positions cannot be
  addressed without a currently valid banker session.
  """

  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Item.EquipmentTransitions
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity.Player.Bank
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.System.Petition, as: PetitionSystem

  def auto_store_in_bag(%State{} = state, source_position, destination_bag) do
    case Bank.authorize_positions(state, [source_position, {destination_bag, 0}]) do
      {:ok, state} ->
        Inventory.auto_store_in_bag(
          state.character.player,
          state.guid,
          source_position,
          destination_bag,
          &ItemStore.get/1
        )
        |> then(&apply_equipment_change(state, &1))

      {:error, state} ->
        reject_remote_bank(state)
    end
  end

  def auto_equip(%{character: character} = state, source_position) do
    case Bank.authorize_positions(state, [source_position]) do
      {:ok, state} ->
        Inventory.auto_equip(
          character.player,
          character.unit,
          Proficiency.from_character(character),
          state.guid,
          source_position,
          &ItemStore.get/1,
          validate_item: &Reputation.validate_item_requirement(character, &1)
        )
        |> then(&apply_equipment_change(state, &1))

      {:error, state} ->
        reject_remote_bank(state)
    end
  end

  def equip_item(%State{guid: owner_guid} = state, item_guid, destination_slot) do
    destination_position = {255, destination_slot}

    with true <- Inventory.equipment_slot?(destination_slot) or Inventory.bag_slot?(destination_slot),
         %Item{item: %{owner: ^owner_guid}} <- ItemStore.get(item_guid),
         {_, _} = source_position when source_position != destination_position <-
           Inventory.find_position(state.character.player, item_guid, :all_owned, &ItemStore.get/1) do
      swap(state, source_position, destination_position)
    else
      _ignored -> state
    end
  end

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
        |> then(&apply_equipment_change(state, &1))

      {:error, state} ->
        reject_remote_bank(state)
    end
  end

  def split(%State{} = state, source_position, destination_position, count) when is_integer(count) and count > 0 do
    with {:ok, state} <- Bank.authorize_positions(state, [source_position, destination_position]),
         source_guid when is_integer(source_guid) <-
           Inventory.item_guid_at(state.character.player, source_position, &ItemStore.get/1),
         %Item{} = source_item <- ItemStore.get(source_guid),
         %Item{} = new_item <- ItemStore.prepare(Item.template(source_item), owner: state.guid, stack_count: count) do
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
          {:ok, result, item} ->
            finish_destroy(state, result, item)

          error ->
            InventoryUpdate.apply(state, error)
        end

      {:error, state} ->
        reject_remote_bank(state)
    end
  end

  defp finish_destroy(state, result, item) do
    state = InventoryUpdate.apply(state, {:ok, %{result | destroyed: [item]}})
    if item.object.entry == 5863, do: PetitionSystem.delete(item.object.guid)
    state
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
        InventoryUpdate.send_failure(error, item1_guid, item2_guid)
        state
    end
  end

  defp reject_remote_bank(state) do
    InventoryUpdate.send_failure(:too_far_away_from_bank, 0, 0)
    state
  end

  defp apply_equipment_change(state, {:ok, %{player: player}} = result) do
    case EquipmentTransitions.validate(state.character, player, &ItemStore.get/1, Time.now()) do
      :ok -> InventoryUpdate.apply(state, result)
      error -> InventoryUpdate.apply(state, error)
    end
  end

  defp apply_equipment_change(state, error), do: InventoryUpdate.apply(state, error)

  defp reject_missing_item(state) do
    InventoryUpdate.send_failure(:item_not_found, 0, 0)
    state
  end
end
