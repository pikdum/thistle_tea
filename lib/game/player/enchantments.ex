defmodule ThistleTea.Game.Player.Enchantments do
  @moduledoc """
  Applies, expires, and evaluates temporary item enchantments owned by a player.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def apply_temporary(
        %{character: %Character{} = character} = state,
        item_guid,
        %Spell{} = spell,
        enchantment_id,
        duration_ms
      ) do
    with %Item{} = item <- ItemStore.get(item_guid),
         {_bag, _slot} = position <- Inventory.find_position(character.player, item_guid, &ItemStore.get/1),
         true <- valid_target?(item, spell),
         true <- not is_nil(ItemEnchantmentLoader.get(enchantment_id)) do
      token = make_ref()
      old_enchantment_id = active_enchantment_id(item)
      item = Item.put_temporary_enchantment(item, enchantment_id, duration_ms, 0, Time.now() + duration_ms, token)
      ItemStore.put(item)
      Process.send_after(self(), {:expire_item_enchantment, item_guid, token}, duration_ms)

      character =
        character |> sync_equipped_item(position, item) |> sync_enchantment_auras(old_enchantment_id, enchantment_id)

      send_updates(character, item, duration_ms)
      %{state | character: character}
    else
      _ -> state
    end
  end

  def expire(%{character: %Character{} = character} = state, item_guid, token) do
    with %Item{} = item <- ItemStore.get(item_guid),
         %{id: id, token: ^token, expires_at: expires_at} <- Item.temporary_enchantment(item),
         true <- expires_at <= Time.now() do
      position = Inventory.find_position(character.player, item_guid, &ItemStore.get/1)
      item = Item.clear_temporary_enchantment(item)
      ItemStore.put(item)
      character = character |> sync_equipped_item(position, item) |> sync_enchantment_auras(id, nil)
      send_updates(character, item, 0)
      %{state | character: character}
    else
      _ -> state
    end
  end

  def restore(%Character{} = character) do
    now = Time.now()

    Inventory.owned_items(character.player, &ItemStore.get/1)
    |> Enum.reduce(character, fn item, character -> restore_item(character, item, now) end)
  end

  def skill_bonus(%Character{} = character, skill_id) do
    now = Time.now()

    Inventory.slots()
    |> Enum.map(&Map.get(character.player, &1))
    |> Enum.map(&ItemStore.get/1)
    |> Enum.reduce(0, fn
      %Item{} = item, total -> total + active_skill_bonus(item, skill_id, now)
      nil, total -> total
    end)
  end

  def weapon_proc(%Character{player: player}) do
    with guid when is_integer(guid) and guid > 0 <- player.mainhand,
         %Item{} = item <- ItemStore.get(guid),
         %{id: enchantment_id, expires_at: expires_at} <- Item.temporary_enchantment(item),
         true <- expires_at > Time.now(),
         %{effects: effects} <- ItemEnchantmentLoader.get(enchantment_id),
         effect when is_map(effect) <- Enum.find(effects, &(&1.type == 1)) do
      %{effect: effect, attack_time_ms: Item.template(item).delay || 2_000}
    else
      _ -> nil
    end
  end

  def weapon_proc(_character), do: nil

  def send_active_timers(%Character{} = character) do
    now = Time.now()

    Inventory.owned_items(character.player, &ItemStore.get/1)
    |> Enum.each(fn item ->
      case Item.temporary_enchantment(item) do
        %{expires_at: expires_at} when expires_at > now -> send_enchant_time(character, item, expires_at - now)
        _ -> :ok
      end
    end)
  end

  defp restore_item(character, item, now) do
    {item, enchantment} = Item.refresh_temporary_enchantment(item, now)
    ItemStore.put(item)
    position = Inventory.find_position(character.player, item.object.guid, &ItemStore.get/1)
    character = sync_equipped_item(character, position, item)

    case enchantment do
      %{expires_at: expires_at, token: token} ->
        remaining_ms = expires_at - now
        Process.send_after(self(), {:expire_item_enchantment, item.object.guid, token}, remaining_ms)
        sync_enchantment_auras(character, nil, active_enchantment_id(item))

      nil ->
        character
    end
  end

  defp active_skill_bonus(item, skill_id, now) do
    case Item.temporary_enchantment(item) do
      %{id: id, expires_at: expires_at} when expires_at > now -> ItemEnchantmentLoader.skill_bonus(id, skill_id)
      _ -> 0
    end
  end

  defp active_enchantment_id(%Item{} = item) do
    now = Time.now()

    case Item.temporary_enchantment(item) do
      %{id: id, expires_at: expires_at} when expires_at > now -> id
      _ -> nil
    end
  end

  defp sync_enchantment_auras(character, removed_enchantment_id, added_enchantment_id) do
    now = Time.now()
    {character, remove_events} = Aura.remove_spells(character, enchantment_spell_ids(removed_enchantment_id), now)

    {character, apply_events} =
      Enum.reduce(enchantment_spell_ids(added_enchantment_id), {character, []}, fn spell_id, {character, events} ->
        case SpellLoader.load(spell_id) do
          %Spell{} = spell ->
            {character, aura_events} =
              Aura.apply_spell(character, character.object.guid, character.unit.level || 1, spell, now)

            {character, events ++ aura_events}

          _ ->
            {character, events}
        end
      end)

    EventSink.emit(character, remove_events ++ apply_events)
  end

  defp enchantment_spell_ids(enchantment_id) when is_integer(enchantment_id) do
    case ItemEnchantmentLoader.get(enchantment_id) do
      %{effects: effects} -> for %{type: 3, spell_id: spell_id} <- effects, is_integer(spell_id), do: spell_id
      _ -> []
    end
  end

  defp enchantment_spell_ids(_enchantment_id), do: []

  defp valid_target?(item, %Spell{equipped_item_class: class, equipped_item_subclass_mask: mask}) do
    template = Item.template(item)
    class_matches? = class < 0 or template.class == class
    subclass_matches? = mask in [0, nil] or (mask &&& 1 <<< template.subclass) != 0
    class_matches? and subclass_matches?
  end

  defp sync_equipped_item(%Character{} = character, {0, slot}, item) do
    %{character | player: Inventory.sync_visible_item(character.player, slot, item)}
  end

  defp sync_equipped_item(character, _position, _item), do: character

  defp send_updates(character, item, duration_ms) do
    Network.send_packet(UpdateObject.item_values_update(item))
    send_enchant_time(character, item, duration_ms)

    %UpdateObject{update_type: :values, object_type: :player}
    |> struct(Map.from_struct(character))
    |> World.broadcast_packet(character)
  end

  defp send_enchant_time(character, item, duration_ms) do
    Network.send_packet(%Message.SmsgItemEnchantTimeUpdate{
      item_guid: item.object.guid,
      slot: Item.temporary_enchantment_slot(),
      duration_seconds: div(duration_ms, 1_000),
      player_guid: character.object.guid
    })
  end
end
