defmodule ThistleTea.Game.Entity.Logic.CombatRatings do
  @moduledoc """
  Player melee avoidance and crit chances following vmangos: crit and dodge
  from per-class agility rates interpolated between level 1 and 60 plus a
  per-class base bonus, parry for classes that learn it, and block/block value
  from an equipped shield. `sync/1` writes the derived percentages to the
  player component fields shown on the character sheet.
  """
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit

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

  @base_avoidance_chance 5.0

  def melee_crit_chance(class, level, agility) do
    class_base_bonus(class) + agility_chance(@crit_agility_rates, class, level, agility)
  end

  def dodge_chance(class, level, agility) do
    class_base_bonus(class) + agility_chance(@dodge_agility_rates, class, level, agility)
  end

  def parry_chance(class) when class in @parry_classes, do: @base_avoidance_chance
  def parry_chance(_class), do: 0.0

  def block_chance(%{} = equipment_bonuses) do
    if Map.get(equipment_bonuses, :shields, 0) > 0, do: @base_avoidance_chance, else: 0.0
  end

  def block_chance(_equipment_bonuses), do: 0.0

  def block_value(%{} = equipment_bonuses, strength) do
    shield_block = Map.get(equipment_bonuses, :shield_block, 0)
    max(shield_block + div(strength || 0, 20) - 1, 0)
  end

  def block_value(_equipment_bonuses, _strength), do: 0

  def sync(%{unit: %Unit{} = unit, player: %Player{} = player} = character) do
    level = unit.level || 1
    agility = unit.agility || 0
    crit = melee_crit_chance(unit.class, level, agility)

    player = %{
      player
      | crit_percentage: crit,
        ranged_crit_percentage: crit,
        dodge_percentage: dodge_chance(unit.class, level, agility),
        parry_percentage: parry_chance(unit.class),
        block_percentage: block_chance(unit.equipment_bonuses || %{})
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
