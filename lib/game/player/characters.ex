defmodule ThistleTea.Game.Player.Characters do
  @moduledoc """
  Character creation flow: validates name uniqueness and the per-account
  limit, assigns the guid and starting equipment, and stores the new
  character.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @character_limit 10

  def create(%Character{} = character, get_template \\ &ItemLoader.get_template/1) do
    with {:exists, nil} <- {:exists, CharacterStore.get_by_name(character.internal.name)},
         {:limit, false} <- {:limit, at_character_limit?(character.account_id)} do
      character =
        character
        |> CharacterStore.create()
        |> assign_starting_items(get_template)
        |> Character.restore_health_and_mana()
        |> CharacterStore.put()

      {:ok, character}
    else
      {:exists, %Character{}} -> {:error, :character_exists}
      {:limit, true} -> {:error, :character_limit}
    end
  end

  def assign_starting_items(
        %Character{object: %{guid: owner_guid}} = character,
        get_template \\ &ItemLoader.get_template/1
      )
      when is_integer(owner_guid) and owner_guid > 0 do
    character.internal.starting_items
    |> then(&assign_items(character, &1, get_template))
  end

  def assign_items(
        %Character{object: %{guid: owner_guid}} = character,
        items,
        get_template \\ &ItemLoader.get_template/1
      )
      when is_integer(owner_guid) and owner_guid > 0 and is_list(items) do
    items
    |> Enum.reduce(character, fn item, char -> assign_item(item, char, get_template) end)
    |> equip_stored_items()
    |> Character.sync_equipment_stats()
  end

  def clear_equipment(%Character{player: player} = character) do
    player =
      Inventory.slots()
      |> Enum.reduce(player, fn slot, player ->
        player
        |> delete_equipped_item(slot)
        |> Map.put(slot, 0)
        |> Map.put(Inventory.visible_entry_field(slot), 0)
      end)

    Character.sync_equipment_stats(%{character | player: player})
  end

  defp at_character_limit?(account_id) do
    length(CharacterStore.for_account(account_id)) >= @character_limit
  end

  defp delete_equipped_item(player, slot) do
    case Map.get(player, slot) do
      guid when is_integer(guid) and guid > 0 -> ItemStore.delete(guid)
      _ -> :ok
    end

    player
  end

  defp assign_item(%{item_id: item_id, amount: amount}, character, get_template) do
    assign_item({item_id, amount}, character, get_template)
  end

  defp assign_item(item_id, character, get_template) when is_integer(item_id) do
    assign_item({item_id, 1}, character, get_template)
  end

  defp assign_item({item_id, amount}, %Character{object: %{guid: owner_guid}} = character, get_template)
       when is_integer(amount) and amount > 0 do
    case ItemStore.create(item_id, owner: owner_guid, stack_count: amount, get_template: get_template) do
      %Item{} = item -> equip_or_store_starting_item(character, item)
      _ -> character
    end
  end

  defp assign_item(_item, character, _get_template), do: character

  defp equip_or_store_starting_item(%Character{} = character, %Item{} = item) do
    case equip_starting_item(character, item) do
      {:ok, character} -> character
      :error -> store_starting_item(character, item)
    end
  end

  defp equip_starting_item(%Character{player: player, unit: unit} = character, %Item{} = item) do
    get_item = &ItemStore.get/1

    with {:ok, slot} <- Inventory.find_equip_slot(player, unit, item, get_item),
         nil <- Inventory.item_guid_at(player, {Inventory.bag_0(), slot}, get_item) do
      {:ok, %{character | player: Inventory.equip(player, slot, item)}}
    else
      _ -> :error
    end
  end

  defp store_starting_item(%Character{object: %{guid: owner_guid}, player: player} = character, %Item{} = item) do
    case Inventory.store(player, owner_guid, item, &ItemStore.get/1) do
      {:ok, result, placement} ->
        persist_inventory_result(result, item, placement)
        %{character | player: result.player}

      _ ->
        ItemStore.delete(item.object.guid)
        character
    end
  end

  defp equip_stored_items(%Character{} = character) do
    character.player
    |> Inventory.owned_items(&ItemStore.get/1)
    |> Enum.reduce(character, &maybe_auto_equip_stored_item/2)
  end

  defp maybe_auto_equip_stored_item(item, %Character{} = character) do
    case Inventory.find_position(character.player, item.object.guid, &ItemStore.get/1) do
      nil -> character
      pos -> auto_equip_stored_item(character, pos)
    end
  end

  defp auto_equip_stored_item(%Character{} = character, pos) do
    if equipment_position?(pos), do: character, else: auto_equip_starting_item(character, pos)
  end

  defp equipment_position?({bag, slot}) do
    bag == Inventory.bag_0() and Inventory.equipment_slot?(slot)
  end

  defp auto_equip_starting_item(%Character{object: %{guid: owner_guid}, player: player, unit: unit} = character, pos) do
    case Inventory.auto_equip(player, unit, owner_guid, pos, &ItemStore.get/1) do
      {:ok, result} ->
        persist_inventory_result(result)
        %{character | player: result.player}

      _ ->
        character
    end
  end

  defp persist_inventory_result(result, item \\ nil, placement \\ nil) do
    Enum.each(result.items, &ItemStore.put/1)
    Enum.each(result.destroyed, fn item -> ItemStore.delete(item.object.guid) end)

    case {item, placement} do
      {_item, {:placed, _pos, placed}} -> ItemStore.put(placed)
      {%Item{} = item, :merged} -> ItemStore.delete(item.object.guid)
      _ -> :ok
    end
  end
end
