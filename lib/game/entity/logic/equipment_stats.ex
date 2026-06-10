defmodule ThistleTea.Game.Entity.Logic.EquipmentStats do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Player.Stats

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
    :arcane
  ]

  @zero Map.new(@bonus_keys, fn key -> {key, 0} end)

  @stat_mods %{0 => :mana, 1 => :health, 3 => :agility, 4 => :strength, 5 => :intellect, 6 => :spirit, 7 => :stamina}

  @stat_fields [
    strength: :strength,
    agility: :agility,
    stamina: :stamina,
    intellect: :intellect,
    spirit: :spirit,
    armor: :normal_resistance,
    holy: :holy_resistance,
    fire: :fire_resistance,
    nature: :nature_resistance,
    frost: :frost_resistance,
    shadow: :shadow_resistance,
    arcane: :arcane_resistance
  ]

  def remove(character) do
    resync(character, fn _guid -> nil end)
  end

  def resync(
        %{unit: %Unit{} = unit, player: %Player{} = player, internal: %Internal{} = internal} = character,
        get_item
      ) do
    old = internal.equipment_bonuses || @zero
    new = player |> Inventory.equipped_templates(get_item) |> bonuses()

    unit =
      unit
      |> apply_stat_deltas(old, new)
      |> apply_health(new)
      |> apply_mana(new)

    %{character | unit: unit, internal: %{internal | equipment_bonuses: new}}
  end

  def bonuses(templates) do
    Enum.reduce(templates, @zero, &add_template/2)
  end

  defp add_template(%ItemTemplate{} = template, acc) do
    acc =
      acc
      |> add(:armor, template.armor)
      |> add(:holy, template.holy_res)
      |> add(:fire, template.fire_res)
      |> add(:nature, template.nature_res)
      |> add(:frost, template.frost_res)
      |> add(:shadow, template.shadow_res)
      |> add(:arcane, template.arcane_res)

    Enum.reduce(1..10, acc, fn i, acc ->
      case Map.get(@stat_mods, Map.get(template, :"stat_type#{i}")) do
        nil -> acc
        key -> add(acc, key, Map.get(template, :"stat_value#{i}"))
      end
    end)
  end

  defp add(acc, key, value) when is_integer(value), do: Map.update!(acc, key, &(&1 + value))
  defp add(acc, _key, _value), do: acc

  defp apply_stat_deltas(%Unit{} = unit, old, new) do
    Enum.reduce(@stat_fields, unit, fn {bonus_key, unit_field}, unit ->
      delta = Map.fetch!(new, bonus_key) - Map.fetch!(old, bonus_key)
      Map.update(unit, unit_field, delta, fn value -> (value || 0) + delta end)
    end)
  end

  defp apply_health(%Unit{base_health: base_health} = unit, new) when is_integer(base_health) do
    max_health = base_health + Stats.stamina_health_bonus(unit.stamina || 0) + new.health
    max_health = max(max_health, 1)
    %{unit | max_health: max_health, health: min(unit.health || 0, max_health)}
  end

  defp apply_health(%Unit{} = unit, _new), do: unit

  defp apply_mana(%Unit{base_mana: base_mana} = unit, new) when is_integer(base_mana) and base_mana > 0 do
    max_mana = base_mana + Stats.mana_bonus(unit.intellect || 0) + new.mana
    max_mana = max(max_mana, 0)
    %{unit | max_power1: max_mana, power1: min(unit.power1 || 0, max_mana)}
  end

  defp apply_mana(%Unit{} = unit, _new), do: unit
end
