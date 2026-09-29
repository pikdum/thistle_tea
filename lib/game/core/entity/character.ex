defmodule ThistleTea.Game.Core.Entity.Character do
  @moduledoc """
  Runtime player entity: account identity plus the component structs
  (Object, Unit, Player, MovementBlock, Internal) that game systems
  pattern-match on, with helpers that sync equipped-weapon inputs into
  the unit's base combat stats.
  """
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Pet.Companion

  defstruct [:id, :account_id, :object, :unit, :player, :movement_block, :internal]

  @base_attack_time 2000
  @base_min_damage 1.0
  @base_max_damage 2.0
  @item_class_weapon 2

  def creature_type(%__MODULE__{unit: %Unit{shapeshift_form: form}}) when form in [1, 3, 4, 5, 8, 14, 15, 16], do: 1

  def creature_type(%__MODULE__{}), do: 7

  def restore_health_and_mana(%__MODULE__{unit: %Unit{} = unit} = character) do
    %{character | unit: %{unit | health: unit.max_health, power1: unit.max_power1}}
  end

  def controlled_guid(%__MODULE__{} = character), do: Companion.active_guid(character)

  def controls?(%__MODULE__{} = character, guid), do: Companion.controls?(character, guid)

  def sync_weapon_inputs(%__MODULE__{} = character, weapons) when is_map(weapons) do
    character
    |> sync_mainhand_inputs(weapon(weapons[:mainhand]))
    |> sync_offhand_inputs(weapon(weapons[:offhand]))
    |> sync_ranged_inputs(weapon(weapons[:ranged]), weapons[:ammo])
  end

  defp weapon(%ItemTemplate{class: @item_class_weapon} = template), do: template
  defp weapon(_template), do: nil

  defp sync_mainhand_inputs(%__MODULE__{unit: %Unit{} = unit} = character, weapon) do
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

  defp sync_offhand_inputs(%__MODULE__{unit: %Unit{} = unit} = character, weapon) do
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

  defp usable_weapon(%__MODULE__{player: %Player{broken_equipment: broken}}, slot, weapon) do
    if slot not in (broken || []), do: weapon
  end

  defp sync_ranged_inputs(%__MODULE__{unit: %Unit{} = unit} = character, weapon, ammo) do
    ammo_dps = ammo_dps(ammo, weapon)

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

  defp ammo_dps(%ItemTemplate{class: 6, subclass: ammo_type, dmg_min1: min, dmg_max1: max}, %ItemTemplate{
         ammo_type: ammo_type
       })
       when is_number(min) and is_number(max), do: (min + max) / 2

  defp ammo_dps(_ammo, _weapon), do: 0.0

  defp positive_or(value, default) do
    case value do
      value when is_number(value) and value > 0 -> value
      _ -> default
    end
  end
end
