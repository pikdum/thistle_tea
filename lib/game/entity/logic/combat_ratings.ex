defmodule ThistleTea.Game.Entity.Logic.CombatRatings do
  @moduledoc """
  Player melee avoidance and crit chances from canonical stats, defense skill,
  learned combat capabilities, equipment, and auras. The same defensive chances
  feed attack resolution and the player fields shown on the character sheet.
  """
  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.Skills

  @warrior 1
  @paladin 2
  @hunter 3
  @rogue 4
  @priest 5
  @shaman 7
  @mage 8
  @warlock 9
  @druid 11

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

  def parry_chance(%{unit: %Unit{}} = entity), do: defensive_chances(entity).parry

  def block_chance(%{unit: %Unit{}, player: %Player{}} = character), do: defensive_chances(character).block

  def block_chance(%{} = equipment_bonuses) do
    if Map.get(equipment_bonuses, :shields, 0) > 0, do: @base_avoidance_chance, else: 0.0
  end

  def block_chance(_equipment_bonuses), do: 0.0

  def defensive_chances(%{unit: %Unit{} = unit, player: %Player{}} = character) do
    proficiency = proficiency(character)
    level = unit.level || 1
    equipment = unit.equipment_bonuses || %{}
    defense_bonus = (Skills.defense_value(character) - Skills.max_for_level(level)) * 0.04
    dodge = dodge_chance(unit.class, level, unit.agility || 0) + Aura.flat_amount(character, :mod_dodge)
    parry = @base_avoidance_chance + Aura.flat_amount(character, :mod_parry_percent)

    block =
      @base_avoidance_chance + Map.get(equipment, :block_chance, 0) +
        Aura.flat_amount(character, :mod_block_percent)

    can_parry? = proficiency.parry? and not Disarm.parry_disabled?(character)
    can_block? = proficiency.block? and block_chance(equipment) > 0

    %{
      dodge: max(dodge + defense_bonus, 0.0),
      parry: if(can_parry?, do: max(parry + defense_bonus, 0.0), else: 0.0),
      block: if(can_block?, do: max(block + defense_bonus, 0.0), else: 0.0)
    }
  end

  def defensive_chances(entity) do
    %{
      dodge: max(@base_avoidance_chance + Aura.flat_amount(entity, :mod_dodge), 0.0),
      parry: max(@base_avoidance_chance + Aura.flat_amount(entity, :mod_parry_percent), 0.0),
      block: max(@base_avoidance_chance + Aura.flat_amount(entity, :mod_block_percent), 0.0)
    }
  end

  defp proficiency(%{internal: %{spellbook: spellbook}}), do: Proficiency.from_spellbook(spellbook)
  defp proficiency(_character), do: %Proficiency{}

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
    defenses = defensive_chances(character)

    player = %{
      player
      | crit_percentage: crit,
        ranged_crit_percentage: crit,
        dodge_percentage: defenses.dodge,
        parry_percentage: defenses.parry,
        block_percentage: defenses.block
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
