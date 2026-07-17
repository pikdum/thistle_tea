defmodule ThistleTea.Game.Entity.Data.Character do
  @moduledoc """
  Runtime player entity: account identity plus the component structs
  (Object, Unit, Player, MovementBlock, Internal) that game systems
  pattern-match on, with helpers that sync equipped-weapon inputs into
  the unit's base combat stats.
  """
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  defstruct [:id, :account_id, :object, :unit, :player, :movement_block, :internal]

  @base_attack_time 2000
  @base_min_damage 1.0
  @base_max_damage 2.0
  @item_class_weapon 2

  def sync_equipment_stats(%__MODULE__{} = character) do
    character
    |> sync_mainhand_inputs()
    |> sync_offhand_inputs()
    |> sync_ranged_inputs()
    |> EquipmentStats.resync(&ItemStore.get/1, &SpellLoader.load/1)
    |> CombatRatings.sync()
  end

  def restore_health_and_mana(%__MODULE__{unit: %Unit{} = unit} = character) do
    %{character | unit: %{unit | health: unit.max_health, power1: unit.max_power1}}
  end

  defp sync_mainhand_inputs(%__MODULE__{unit: %Unit{} = unit} = character) do
    {delay, weapon_min, weapon_max} =
      case mainhand_weapon(character) do
        %ItemTemplate{} = weapon ->
          {positive_or(weapon.delay, @base_attack_time), positive_or(weapon.dmg_min1, @base_min_damage),
           positive_or(weapon.dmg_max1, @base_max_damage)}

        _ ->
          {@base_attack_time, @base_min_damage, @base_max_damage}
      end

    unit =
      %{
        unit
        | base_melee_attack_time: delay,
          base_attack_time: delay,
          base_min_damage: weapon_min,
          base_max_damage: weapon_max
      }

    %{character | unit: unit}
  end

  defp sync_offhand_inputs(%__MODULE__{unit: %Unit{} = unit, player: %Player{visible_item_17_0: entry}} = character) do
    weapon =
      case is_integer(entry) and entry > 0 and ItemLoader.get_template(entry) do
        %ItemTemplate{class: @item_class_weapon} = template -> template
        _ -> nil
      end

    unit =
      if weapon do
        %{
          unit
          | offhand_attack_time: positive_or(weapon.delay, @base_attack_time),
            base_offhand_min_damage: positive_or(weapon.dmg_min1, 0.0),
            base_offhand_max_damage: positive_or(weapon.dmg_max1, 0.0)
        }
      else
        %{
          unit
          | offhand_attack_time: @base_attack_time,
            base_offhand_min_damage: nil,
            base_offhand_max_damage: nil,
            min_offhand_damage: 0.0,
            max_offhand_damage: 0.0
        }
      end

    %{character | unit: unit}
  end

  defp mainhand_weapon(%__MODULE__{player: %Player{visible_item_16_0: entry}}) when is_integer(entry) and entry > 0 do
    ItemLoader.get_template(entry)
  end

  defp mainhand_weapon(%__MODULE__{}), do: nil

  defp sync_ranged_inputs(
         %__MODULE__{unit: %Unit{} = unit, player: %Player{visible_item_18_0: entry, ammo_id: ammo_id}} = character
       ) do
    weapon =
      case is_integer(entry) and entry > 0 and ItemLoader.get_template(entry) do
        %ItemTemplate{class: @item_class_weapon} = template -> template
        _ -> nil
      end

    ammo_dps = ammo_dps(ammo_id, weapon)

    unit =
      if weapon do
        speed = positive_or(weapon.delay, @base_attack_time) / 1_000

        %{
          unit
          | base_ranged_attack_time: positive_or(weapon.delay, @base_attack_time),
            ranged_attack_time: positive_or(weapon.delay, @base_attack_time),
            base_ranged_min_damage: positive_or(weapon.dmg_min1, 0.0) + ammo_dps * speed,
            base_ranged_max_damage: positive_or(weapon.dmg_max1, 0.0) + ammo_dps * speed
        }
      else
        %{
          unit
          | base_ranged_attack_time: nil,
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
