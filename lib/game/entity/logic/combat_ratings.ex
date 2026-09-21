defmodule ThistleTea.Game.Entity.Logic.CombatRatings do
  @moduledoc """
  Player melee avoidance and crit chances following vmangos: crit and dodge
  from per-class agility rates interpolated between level 1 and 60 plus a
  per-class base bonus, parry for classes that learn it, and block/block value
  from an equipped shield. `sync/1` writes the derived percentages to the
  player component fields shown on the character sheet.
  """
  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Disarm

  @warrior 1
  @paladin 2
  @hunter 3
  @rogue 4
  @priest 5
  @shaman 7
  @mage 8
  @warlock 9
  @druid 11

  @parry_classes [@warrior, @paladin, @hunter, @rogue, @shaman]

  @crit_agility_rates %{
    @warrior => {3.9, 20.0},
    @paladin => {4.6, 20.0},
    @hunter => {3.5, 53.0},
    @rogue => {2.2, 29.0},
    @priest => {11.0, 20.0},
    @shaman => {4.6, 20.0},
    @mage => {12.9, 20.0},
    @warlock => {8.4, 20.0},
    @druid => {4.6, 20.0}
  }

  @dodge_agility_rates %{
    @warrior => {3.9, 20.0},
    @paladin => {4.6, 20.0},
    @hunter => {1.8, 26.5},
    @rogue => {1.1, 14.5},
    @priest => {11.0, 20.0},
    @shaman => {4.6, 20.0},
    @mage => {12.9, 20.0},
    @warlock => {8.4, 20.0},
    @druid => {4.6, 20.0}
  }

  @class_base_bonus %{
    @paladin => 0.7,
    @priest => 3.0,
    @shaman => 1.7,
    @mage => 3.2,
    @warlock => 2.0,
    @druid => 0.9
  }

  @spell_crit_rates %{
    @paladin => {3.70, 14.77, 0.65},
    @priest => {2.97, 10.03, 0.82},
    @shaman => {3.54, 11.51, 0.80},
    @mage => {3.70, 14.77, 0.65},
    @warlock => {3.18, 11.30, 0.82},
    @druid => {3.33, 12.41, 0.79}
  }

  @base_avoidance_chance 5.0

  def melee_crit_chance(class, level, agility) do
    class_base_bonus(class) + agility_chance(@crit_agility_rates, class, level, agility)
  end

  def dodge_chance(class, level, agility) do
    class_base_bonus(class) + agility_chance(@dodge_agility_rates, class, level, agility)
  end

  def spell_crit_chance(class, level, intellect) do
    case Map.get(@spell_crit_rates, class) do
      {base, rate0, rate1} -> max(base + intellect / (rate0 + rate1 * max(level, 1)), 0.0)
      nil -> 0.0
    end
  end

  def parry_chance(class) when class in @parry_classes, do: @base_avoidance_chance
  def parry_chance(_class), do: 0.0

  def block_chance(%{unit: %Unit{} = unit, player: %Player{}} = character) do
    if block_chance(unit.equipment_bonuses || %{}) > 0 do
      bonus = Map.get(unit.equipment_bonuses || %{}, :block_chance, 0)
      max(@base_avoidance_chance + bonus + Aura.flat_amount(character, :mod_block_percent), 0.0)
    else
      0.0
    end
  end

  def block_chance(%{} = equipment_bonuses) do
    if Map.get(equipment_bonuses, :shields, 0) > 0, do: @base_avoidance_chance, else: 0.0
  end

  def block_chance(_equipment_bonuses), do: 0.0

  def block_value(%{unit: %Unit{} = unit, player: %Player{}} = character) do
    flat =
      Map.get(unit.equipment_bonuses || %{}, :shield_block, 0) + Aura.flat_amount(character, :mod_shield_block_value)

    max(trunc((flat + (unit.strength || 0) / 20 - 1) * block_value_multiplier(unit.auras)), 0)
  end

  def block_value(%{unit: %Unit{} = unit}) do
    div(unit.level || 1, 2) + div(unit.strength || 0, 20)
  end

  def block_value(_entity), do: 0

  def block_value(%{} = equipment_bonuses, strength) do
    shield_block = Map.get(equipment_bonuses, :shield_block, 0)
    max(shield_block + div(strength || 0, 20) - 1, 0)
  end

  def block_value(_equipment_bonuses, _strength), do: 0

  defp block_value_multiplier(holders) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %AuraData{type: :mod_shield_block_value_pct, amount: amount} <- auras,
        is_integer(amount),
        reduce: 1.0 do
      multiplier -> multiplier * max(100 + amount * max(stacks || 1, 1), 0) / 100
    end
  end

  defp block_value_multiplier(_holders), do: 1.0

  def sync(%{unit: %Unit{} = unit, player: %Player{} = player} = character) do
    level = unit.level || 1
    agility = unit.agility || 0
    crit = max(melee_crit_chance(unit.class, level, agility) + Aura.flat_amount(character, :mod_crit_percent), 0.0)
    dodge = max(dodge_chance(unit.class, level, agility) + Aura.flat_amount(character, :mod_dodge), 0.0)
    parry = max(parry_chance(unit.class) + Aura.flat_amount(character, :mod_parry_percent), 0.0)

    player = %{
      player
      | crit_percentage: crit,
        ranged_crit_percentage: crit,
        dodge_percentage: dodge,
        parry_percentage: if(Disarm.parry_disabled?(character), do: 0.0, else: parry),
        block_percentage: block_chance(character)
    }

    %{character | player: player}
  end

  def sync(entity), do: entity

  defp class_base_bonus(class), do: Map.get(@class_base_bonus, class, 0.0)

  defp agility_chance(rates, class, level, agility) do
    {level1, level60} = Map.get(rates, class, {20.0, 20.0})
    level = level |> max(1) |> min(60)
    rate = level1 * (60 - level) / 59 + level60 * (level - 1) / 59

    agility / rate
  end
end
