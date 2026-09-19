defmodule ThistleTea.Game.Player.Enchantments do
  @moduledoc """
  Applies owned item enchants, commits permanent enchant costs atomically,
  and restores temporary enchant timers. Equipment owns all passive bonuses.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Enchantments, as: EnchantmentLogic
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Shaman
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def apply_permanent(
        %{character: %Character{} = character} = state,
        guid,
        spell,
        enchantment_id,
        cast_item_guid \\ nil
      ) do
    with {bag, slot} <- Inventory.find_position(character.player, guid, &ItemStore.get/1),
         %Item{} = item <- ItemStore.get(guid),
         :ok <- EnchantmentLogic.validate_item(character, spell, item),
         true <- not is_nil(ItemEnchantmentLoader.get(enchantment_id)),
         true <- tools_present?(character, spell),
         {:ok, changes} <- plan_costs(character, spell, cast_item_guid),
         %Item{} <- ChangeSet.get_item(changes, guid, &ItemStore.get/1) do
      item = Item.put_permanent_enchantment(item, enchantment_id)

      player =
        if bag == Inventory.bag_0(), do: Inventory.sync_visible_item(changes.player, slot, item), else: changes.player

      character = %{character | player: player} |> advance_skill(spell, cast_item_guid)
      changes = ChangeSet.absorb(changes, %{player: character.player, items: [item], destroyed: []})
      InventoryUpdate.apply(%{state | character: character}, {:ok, changes})
    else
      {:error, reason} -> fail(state, spell, reason)
      {:error, _reason, _first, _second} -> fail(state, spell, :reagents)
      _ -> fail(state, spell, :item_gone)
    end
  end

  defp tools_present?(character, %Spell{tools: tools}) do
    Enum.all?(tools, fn entry -> Inventory.count_entry(character.player, entry, &ItemStore.get/1) > 0 end)
  end

  defp plan_costs(character, spell, cast_item_guid) do
    reagents = if character.internal.godmode, do: [], else: spell.reagents

    batch =
      Enum.reduce(reagents, Batch.new(character.player), fn {entry, count}, batch ->
        Batch.remove(batch, entry, count)
      end)

    batch = if is_integer(cast_item_guid), do: Batch.remove_item(batch, cast_item_guid, 1), else: batch

    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} -> {:ok, changes}
      _error -> {:error, :reagents}
    end
  end

  defp advance_skill(character, spell, nil) do
    EnchantmentLogic.skill_up(character, ItemEnchantmentLoader.recipe(spell.id), :rand.uniform(100) - 1)
  end

  defp advance_skill(character, _spell, _cast_item_guid), do: character

  defp fail(state, spell, reason) do
    Network.send_packet(Message.SmsgCastResult.failure(spell.id, reason))
    state
  end

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
      item = Item.put_temporary_enchantment(item, enchantment_id, duration_ms, 0, Time.now() + duration_ms, token)
      ItemStore.put(item)
      Process.send_after(self(), {:expire_item_enchantment, item_guid, token}, duration_ms)
      character = character |> sync_visible_item(position, item) |> Character.sync_equipment_stats()
      send_updates(character, item, duration_ms)
      %{state | character: character}
    else
      _ -> state
    end
  end

  def expire(%{character: %Character{} = character} = state, item_guid, token) do
    with %Item{} = item <- ItemStore.get(item_guid),
         %{token: ^token, expires_at: expires_at} <- Item.temporary_enchantment(item),
         true <- expires_at <= Time.now(),
         {_bag, _slot} = position <- Inventory.find_position(character.player, item_guid, &ItemStore.get/1) do
      item = Item.clear_temporary_enchantment(item)
      ItemStore.put(item)
      character = character |> sync_visible_item(position, item) |> Character.sync_equipment_stats()
      send_updates(character, item, 0)
      %{state | character: character}
    else
      _ -> state
    end
  end

  def restore(%Character{} = character) do
    now = Time.now()

    character.player
    |> Inventory.owned_items(&ItemStore.get/1)
    |> Enum.reduce(character, fn item, character -> restore_item(character, item, now) end)
    |> Character.sync_equipment_stats()
  end

  def skill_bonus(%Character{} = character, skill_id) do
    character
    |> Character.equipment_enchantments(Time.now())
    |> Enum.reduce(0, fn {_slot, _item, _enchant_slot, enchantment}, total ->
      total + Map.get(enchantment.skill_bonuses, skill_id, 0)
    end)
  end

  def trigger_weapon_procs(%Character{} = character, payload) do
    hand = Map.get(payload, :hand, :mainhand)

    Enum.reduce(weapon_procs(character, hand), character, fn proc, character ->
      Shaman.trigger_weapon_enchant(character, payload, proc, ItemEnchantmentLoader.proc_ppm(proc.effect.spell_id))
    end)
  end

  def weapon_procs(%Character{} = character, hand) do
    for {^hand, item, _enchant_slot, enchantment} <- Character.equipment_enchantments(character, Time.now()),
        weapon_available?(character, hand),
        effect <- enchantment.effects,
        effect.type == 1 do
      %{
        effect: effect,
        proc_spell: SpellLoader.load(effect.spell_id),
        attack_time_ms: Item.template(item).delay || 2_000
      }
    end
  end

  defp weapon_available?(%Character{unit: %{class: 11, shapeshift_form: form}}, _hand) when form in [1, 5, 8], do: false
  defp weapon_available?(character, :mainhand), do: not Disarm.unarmed?(character)
  defp weapon_available?(_character, _hand), do: true

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

    case enchantment do
      %{expires_at: expires_at, token: token} ->
        Process.send_after(self(), {:expire_item_enchantment, item.object.guid, token}, expires_at - now)

      nil ->
        :ok
    end

    sync_visible_item(character, position, item)
  end

  defp valid_target?(item, %Spell{equipped_item_class: class, equipped_item_subclass_mask: mask}) do
    template = Item.template(item)
    (class < 0 or template.class == class) and (mask in [0, nil] or (mask &&& 1 <<< template.subclass) != 0)
  end

  defp sync_visible_item(%Character{} = character, {bag, slot}, item) when bag in [0, 255] do
    %{character | player: Inventory.sync_visible_item(character.player, slot, item)}
  end

  defp sync_visible_item(character, _position, _item), do: character

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
