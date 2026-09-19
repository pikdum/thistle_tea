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
                :block_chance,
                :shield_block,
                :mainhand_damage,
                :offhand_damage,
                :ranged_damage
              ] ++ @spell_damage_keys

  @zero @bonus_keys |> Map.new(fn key -> {key, 0} end) |> Map.put(:spell_damage_versus, [])

  @spelltrigger_on_equip 1

  @stat_mods %{0 => :mana, 1 => :health, 3 => :agility, 4 => :strength, 5 => :intellect, 6 => :spirit, 7 => :stamina}

  def resync(character, get_item, get_spell \\ fn _spell_id -> nil end, enchantments \\ [])

  def resync(%{unit: %Unit{} = unit, player: %Player{} = player} = character, get_item, get_spell, enchantments) do
    bonuses = player |> Inventory.equipped_templates(get_item) |> bonuses(get_spell)
    bonuses = Enum.reduce(enchantments, bonuses, &add_enchantment(&2, &1, unit.class))
    unit = %{unit | equipment_bonuses: bonuses} |> Stats.recompute()
    player = apply_spell_damage_fields(player, bonuses)

    %{character | unit: unit, player: player}
  end

  defp add_enchantment(acc, {slot, item, _enchant_slot, enchantment}, class) do
    Enum.reduce(enchantment.effects, acc, fn
      %{type: 2, amount: amount}, acc ->
        add_weapon_damage(acc, slot, amount)

      %{type: 4, amount: amount, spell_id: school}, acc ->
        add(acc, Enum.at([:armor | tl(@schools)], school), amount)

      %{type: 5, amount: amount, spell_id: stat}, acc ->
        add(acc, Map.get(@stat_mods, stat), amount)

      %{type: 6, amount: amount}, acc when class == 7 ->
        add_weapon_damage(acc, slot, amount * (item.internal.template.delay || 0) / 1_000)

      _effect, acc ->
        acc
    end)
  end

  defp add_weapon_damage(acc, :mainhand, amount), do: add(acc, :mainhand_damage, amount)
  defp add_weapon_damage(acc, :offhand, amount), do: add(acc, :offhand_damage, amount)
  defp add_weapon_damage(acc, :ranged, amount), do: add(acc, :ranged_damage, amount)
  defp add_weapon_damage(acc, _slot, _amount), do: acc

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

      %Effect{type: :apply_aura, aura: :mod_flat_spell_damage_versus, misc_value: mask} = effect, acc
      when is_integer(mask) ->
        Map.update!(acc, :spell_damage_versus, &[{mask, Effect.damage_roll(effect)} | &1])

      %Effect{type: :apply_aura, aura: :mod_attack_power} = effect, acc ->
        add(acc, :attack_power, Effect.damage_roll(effect))

      %Effect{type: :apply_aura, aura: :mod_ranged_haste} = effect, acc ->
        add(acc, :ranged_haste, Effect.damage_roll(effect))

      %Effect{type: :apply_aura, aura: :mod_shield_block_value} = effect, acc ->
        add(acc, :shield_block, Effect.damage_roll(effect))

      %Effect{type: :apply_aura, aura: :mod_block_percent} = effect, acc ->
        add(acc, :block_chance, Effect.damage_roll(effect))

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

  defp add(acc, key, value) when is_number(value) and not is_nil(key), do: Map.update!(acc, key, &(&1 + value))
  defp add(acc, _key, _value), do: acc
end
