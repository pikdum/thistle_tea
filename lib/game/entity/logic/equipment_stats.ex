defmodule ThistleTea.Game.Entity.Logic.EquipmentStats do
  @moduledoc """
  Computes `unit.equipment_bonuses` from the equipped item templates — stats,
  resistances, and passive equip-spell auras — as one of the canonical inputs
  to the stat recompute pipeline.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]
  @spell_damage_keys Enum.map(@schools, fn school -> :"spell_#{school}" end)

  @bonus_keys [
                :strength,
                :agility,
                :stamina,
                :intellect,
                :spirit,
                :health,
                :mana,
                :armor,
                :holy,
                :fire,
                :nature,
                :frost,
                :shadow,
                :arcane,
                :healing,
                :attack_power,
                :ranged_haste,
                :shields,
                :shield_block
              ] ++ @spell_damage_keys

  @zero Map.new(@bonus_keys, fn key -> {key, 0} end)

  @spelltrigger_on_equip 1

  @stat_mods %{0 => :mana, 1 => :health, 3 => :agility, 4 => :strength, 5 => :intellect, 6 => :spirit, 7 => :stamina}

  def resync(character, get_item, get_spell \\ fn _spell_id -> nil end)

  def resync(%{unit: %Unit{} = unit, player: %Player{} = player} = character, get_item, get_spell) do
    bonuses = player |> Inventory.equipped_templates(get_item) |> bonuses(get_spell)
    unit = %{unit | equipment_bonuses: bonuses} |> Stats.recompute()
    player = apply_spell_damage_fields(player, bonuses)

    %{character | unit: unit, player: player}
  end

  def bonuses(templates, get_spell \\ fn _spell_id -> nil end) do
    Enum.reduce(templates, @zero, &add_template(&2, &1, get_spell))
  end

  defp add_template(acc, %ItemTemplate{} = template, get_spell) do
    acc =
      acc
      |> add(:armor, template.armor)
      |> add(:holy, template.holy_res)
      |> add(:fire, template.fire_res)
      |> add(:nature, template.nature_res)
      |> add(:frost, template.frost_res)
      |> add(:shadow, template.shadow_res)
      |> add(:arcane, template.arcane_res)
      |> add_shield(template)
      |> add_equip_spells(template, get_spell)

    Enum.reduce(1..10, acc, fn i, acc ->
      case Map.get(@stat_mods, Map.get(template, :"stat_type#{i}")) do
        nil -> acc
        key -> add(acc, key, Map.get(template, :"stat_value#{i}"))
      end
    end)
  end

  @inventory_type_shield 14

  defp add_shield(acc, %ItemTemplate{inventory_type: @inventory_type_shield} = template) do
    acc
    |> add(:shields, 1)
    |> add(:shield_block, template.block || 0)
  end

  defp add_shield(acc, _template), do: acc

  defp add_equip_spells(acc, %ItemTemplate{} = template, get_spell) do
    Enum.reduce(1..5, acc, fn i, acc ->
      spell_id = Map.get(template, :"spellid_#{i}")
      trigger = Map.get(template, :"spelltrigger_#{i}")

      if is_integer(spell_id) and spell_id > 0 and trigger == @spelltrigger_on_equip do
        add_spell_auras(acc, get_spell.(spell_id))
      else
        acc
      end
    end)
  end

  defp add_spell_auras(acc, %Spell{effects: effects}) do
    Enum.reduce(effects, acc, fn
      %Effect{type: :apply_aura, aura: :mod_damage_done} = effect, acc ->
        add_schools(acc, effect.misc_value, Effect.damage_roll(effect))

      %Effect{type: :apply_aura, aura: :mod_healing_done} = effect, acc ->
        add(acc, :healing, Effect.damage_roll(effect))

      %Effect{type: :apply_aura, aura: :mod_attack_power} = effect, acc ->
        add(acc, :attack_power, Effect.damage_roll(effect))

      %Effect{type: :apply_aura, aura: :mod_ranged_haste} = effect, acc ->
        add(acc, :ranged_haste, Effect.damage_roll(effect))

      _effect, acc ->
        acc
    end)
  end

  defp add_spell_auras(acc, _spell), do: acc

  defp add_schools(acc, mask, amount) when is_integer(mask) do
    @schools
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {school, index}, acc ->
      if (mask &&& 1 <<< index) == 0 do
        acc
      else
        add(acc, :"spell_#{school}", amount)
      end
    end)
  end

  defp add_schools(acc, _mask, _amount), do: acc

  defp apply_spell_damage_fields(%Player{} = player, bonuses) do
    Enum.reduce(@schools, player, fn school, player ->
      Map.put(player, :"mod_damage_done_pos_#{school}", Map.fetch!(bonuses, :"spell_#{school}"))
    end)
  end

  defp add(acc, key, value) when is_integer(value), do: Map.update!(acc, key, &(&1 + value))
  defp add(acc, _key, _value), do: acc
end
