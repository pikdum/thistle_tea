defmodule ThistleTea.Game.World.Entity.Player.Characters do
  @moduledoc """
  Character screen flow. Creation validates name uniqueness and the
  per-account limit, assigns the guid and starting equipment, and stores the
  new character; the character list projects each stored character with its
  visible gear and guild.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Network.Message.SmsgCharEnum
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.Equipment
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Items
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem

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

  def enum(account_id) do
    characters = account_id |> CharacterStore.for_account() |> Enum.map(&enum_entry/1)
    %SmsgCharEnum{amount_of_characters: length(characters), characters: characters}
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
    |> Equipment.sync_stats()
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

    Equipment.sync_stats(%{character | player: player})
  end

  defp enum_entry(%Character{} = character) do
    {x, y, z, _o} = character.movement_block.position

    %SmsgCharEnum.Character{
      guid: character.id,
      name: character.internal.name,
      race: character.unit.race,
      class: character.unit.class,
      gender: character.unit.gender,
      skin: character.player.skin,
      face: character.player.face,
      hair_style: character.player.hair_style,
      hair_color: character.player.hair_color,
      facial_hair: character.player.facial_hair,
      level: character.unit.level,
      area: character.internal.area,
      map: character.internal.world.map_id,
      position: {x, y, z},
      guild_id: guild_id(character.object.guid),
      flags: 0,
      first_login: 0,
      pet_display_id: 0,
      pet_level: 0,
      pet_family: 0,
      equipment:
        Enum.map(Inventory.slots(), &enum_gear(Inventory.equipment_entry(character.player, &1, include_broken: true))),
      first_bag_display_id: 0,
      first_bag_inventory_type: 0
    }
  end

  defp enum_gear(entry) when is_integer(entry) and entry > 0 do
    case ItemLoader.get_template(entry) do
      %ItemTemplate{} = template ->
        %SmsgCharEnum.CharacterGear{equipment_display_id: template.display_id, inventory_type: template.inventory_type}

      nil ->
        enum_gear(0)
    end
  end

  defp enum_gear(_entry), do: %SmsgCharEnum.CharacterGear{equipment_display_id: 0, inventory_type: 0}

  defp guild_id(guid) do
    case GuildSystem.group_of(guid) do
      %{id: id} -> id
      nil -> 0
    end
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

  defp assign_item({item_id, amount}, %Character{} = character, get_template) when is_integer(amount) and amount > 0 do
    case get_template.(item_id) do
      %ItemTemplate{} = template -> assign_template(character, template, amount)
      _missing -> character
    end
  end

  defp assign_item(_item, character, _get_template), do: character

  defp assign_template(%Character{} = character, %ItemTemplate{} = template, count) do
    if count <= max(template.stackable || 1, 1) do
      item = ItemStore.create(template, owner: character.object.guid, stack_count: count)
      equip_or_store_starting_item(character, item)
    else
      assign_stacks(character, template, count)
    end
  end

  defp assign_stacks(%Character{} = character, %ItemTemplate{} = template, count) do
    case Items.plan_store(character, template, count) do
      {:ok, changes, _position} -> InventoryUpdate.apply(character, {:ok, changes})
      {:error, _reason} -> character
    end
  end

  defp equip_or_store_starting_item(%Character{} = character, %Item{} = item) do
    case equip_starting_item(character, item) do
      {:ok, character} -> character
      :error -> store_starting_item(character, item)
    end
  end

  defp equip_starting_item(%Character{player: player, unit: unit} = character, %Item{} = item) do
    get_item = &ItemStore.get/1

    with {:ok, slot} <- Inventory.find_equip_slot(player, unit, Proficiency.all(), item, get_item),
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
    case Inventory.auto_equip(player, unit, Proficiency.all(), owner_guid, pos, &ItemStore.get/1) do
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
