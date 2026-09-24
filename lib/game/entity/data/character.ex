defmodule ThistleTea.Game.Entity.Data.Character do
  @moduledoc """
  Runtime player entity: account identity plus the component structs
  (Object, Unit, Player, MovementBlock, Internal) that game systems
  pattern-match on, with helpers that sync equipped-weapon inputs into
  the unit's base combat stats.
  """
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.EquipmentSets
  alias ThistleTea.Game.Entity.Logic.EquipmentSpells
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.ItemSet, as: ItemSetLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  defstruct [:id, :account_id, :object, :unit, :player, :movement_block, :internal]

  @base_attack_time 2000
  @base_min_damage 1.0
  @base_max_damage 2.0
  @item_class_weapon 2

  def creature_type(%__MODULE__{unit: %Unit{shapeshift_form: form}}) when form in [1, 3, 4, 5, 8, 14, 15, 16], do: 1

  def creature_type(%__MODULE__{}), do: 7

  def sync_equipment_stats(%__MODULE__{} = character) do
    character = %{character | player: Inventory.sync_broken_equipment(character.player, &ItemStore.get/1)}
    now = Time.now()
    enchantments = equipment_enchantments(character, now)
    templates = Inventory.equipped_templates(character.player, &ItemStore.get/1)
    set_sources = EquipmentSets.sources(character, templates, &ItemSetLoader.get/1)
    equip_sources = character.player |> Inventory.usable_equipped_items(&ItemStore.get/1) |> EquipmentSpells.sources()

    character
    |> sync_mainhand_inputs()
    |> sync_offhand_inputs()
    |> sync_ranged_inputs()
    |> EquipmentStats.resync(&ItemStore.get/1, &SpellLoader.load/1, enchantments)
    |> EquipmentAuras.sync(enchantments, &SpellLoader.load/1, now, set_sources ++ equip_sources)
    |> CombatRatings.sync()
  end

  def equipment_enchantments(%__MODULE__{player: player}, now) do
    for slot <- Inventory.slots(),
        guid = Map.get(player, slot),
        %Item{} = item <- [ItemStore.get(guid)],
        not Item.broken?(item),
        {enchant_slot, id} <- Item.active_enchantments(item, now),
        enchantment = ItemEnchantmentLoader.get(id),
        not is_nil(enchantment),
        do: {slot, item, enchant_slot, enchantment}
  end

  def restore_health_and_mana(%__MODULE__{unit: %Unit{} = unit} = character) do
    %{character | unit: %{unit | health: unit.max_health, power1: unit.max_power1}}
  end

  def controlled_guid(%__MODULE__{} = character), do: Companion.active_guid(character)

  def controls?(%__MODULE__{} = character, guid), do: Companion.controls?(character, guid)

  defp sync_mainhand_inputs(%__MODULE__{unit: %Unit{} = unit} = character) do
    weapon = weapon_template(character, :mainhand)

    {delay, weapon_min, weapon_max} =
      case usable_weapon(character, :mainhand, weapon) do
        %ItemTemplate{} = weapon ->
          {positive_or(weapon.delay, @base_attack_time), positive_or(weapon.dmg_min1, @base_min_damage),
           positive_or(weapon.dmg_max1, @base_max_damage)}

        _ ->
          {@base_attack_time, @base_min_damage, @base_max_damage}
      end

    unit =
      %{
        unit
        | mainhand_weapon: weapon,
          base_melee_attack_time: delay,
          base_min_damage: weapon_min,
          base_max_damage: weapon_max
      }

    %{character | unit: unit}
  end

  defp sync_offhand_inputs(%__MODULE__{unit: %Unit{} = unit} = character) do
    weapon = weapon_template(character, :offhand)

    unit =
      if usable_weapon(character, :offhand, weapon) do
        %{
          unit
          | offhand_weapon: weapon,
            base_offhand_attack_time: positive_or(weapon.delay, @base_attack_time),
            base_offhand_min_damage: positive_or(weapon.dmg_min1, 0.0),
            base_offhand_max_damage: positive_or(weapon.dmg_max1, 0.0)
        }
      else
        %{
          unit
          | offhand_weapon: weapon,
            base_offhand_attack_time: @base_attack_time,
            base_offhand_min_damage: nil,
            base_offhand_max_damage: nil,
            min_offhand_damage: 0.0,
            max_offhand_damage: 0.0
        }
      end

    %{character | unit: unit}
  end

  defp weapon_template(%__MODULE__{player: %Player{} = player}, slot) do
    case ItemLoader.get_template(Inventory.equipment_entry(player, slot, include_broken: true)) do
      %ItemTemplate{class: @item_class_weapon} = template -> template
      _ -> nil
    end
  end

  defp usable_weapon(%__MODULE__{player: %Player{broken_equipment: broken}}, slot, weapon) do
    if slot not in (broken || []), do: weapon
  end

  defp sync_ranged_inputs(%__MODULE__{unit: %Unit{} = unit, player: %Player{ammo_id: ammo_id}} = character) do
    weapon = weapon_template(character, :ranged)

    ammo_dps = ammo_dps(ammo_id, weapon)

    unit =
      if usable_weapon(character, :ranged, weapon) do
        speed = positive_or(weapon.delay, @base_attack_time) / 1_000

        %{
          unit
          | ranged_weapon: weapon,
            base_ranged_attack_time: positive_or(weapon.delay, @base_attack_time),
            base_ranged_min_damage: positive_or(weapon.dmg_min1, 0.0) + ammo_dps * speed,
            base_ranged_max_damage: positive_or(weapon.dmg_max1, 0.0) + ammo_dps * speed
        }
      else
        %{
          unit
          | ranged_weapon: weapon,
            base_ranged_attack_time: nil,
            ranged_attack_time: @base_attack_time,
            base_ranged_min_damage: nil,
            base_ranged_max_damage: nil,
            min_ranged_damage: 0.0,
            max_ranged_damage: 0.0
        }
      end

    %{character | unit: unit}
  end

  defp ammo_dps(ammo_id, %ItemTemplate{ammo_type: ammo_type}) when is_integer(ammo_id) and ammo_id > 0 do
    case ItemLoader.get_template(ammo_id) do
      %ItemTemplate{class: 6, subclass: ^ammo_type, dmg_min1: min, dmg_max1: max}
      when is_number(min) and is_number(max) ->
        (min + max) / 2

      _ ->
        0.0
    end
  end

  defp ammo_dps(_ammo_id, _weapon), do: 0.0

  defp positive_or(value, default) do
    case value do
      value when is_number(value) and value > 0 -> value
      _ -> default
    end
  end
end
