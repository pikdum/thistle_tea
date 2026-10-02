defmodule ThistleTea.Game.World.Entity.Player.Stats do
  @moduledoc false

  alias ThistleTea.DB.Mangos.PlayerClassLevelStats
  alias ThistleTea.DB.Mangos.PlayerLevelStats
  alias ThistleTea.DB.Mangos.PlayerXpForLevel
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Player.Experience
  alias ThistleTea.Game.Core.Player.PlayedTime
  alias ThistleTea.Game.Core.Player.Rest
  alias ThistleTea.Game.Core.Player.Talents
  alias ThistleTea.Game.Core.Skills
  alias ThistleTea.Game.Core.Stats, as: StatsCore
  alias ThistleTea.Game.Core.Stats.CombatRatings
  alias ThistleTea.Game.Core.Stats.SpellPower
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity.Player.Equipment
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  defstruct [
    :race,
    :class,
    :level,
    :strength,
    :agility,
    :stamina,
    :intellect,
    :spirit,
    :base_health,
    :base_mana,
    :max_health,
    :max_mana,
    :next_level_xp
  ]

  def get(race, class, level) do
    with %PlayerLevelStats{} = level_stats <- PlayerLevelStats.get(race, class, level),
         %PlayerClassLevelStats{} = class_stats <- PlayerClassLevelStats.get(class, level) do
      stats = build(level_stats, class_stats)
      {:ok, stats}
    else
      _ -> {:error, :not_found}
    end
  end

  def get!(race, class, level) do
    case get(race, class, level) do
      {:ok, stats} -> stats
      {:error, reason} -> raise "missing player stats for race=#{race} class=#{class} level=#{level}: #{reason}"
    end
  end

  def next_level_xp(level) do
    if level >= max_level() do
      0
    else
      case PlayerXpForLevel.get(level) do
        %PlayerXpForLevel{xp_for_next_level: xp} when is_integer(xp) -> xp
        _ -> 0
      end
    end
  end

  def max_level, do: PlayerXpForLevel.max_level()

  def gain_xp(%Character{} = character, amount) do
    Experience.gain_xp(character, amount,
      max_level: max_level(),
      next_level_xp: &next_level_xp/1,
      level_up: &level_up/2
    )
  end

  defp level_up(%Character{unit: %Unit{race: race, class: class}} = character, new_level) do
    old_stats = from_character(character)
    new_stats = get!(race, class, new_level)

    character =
      character
      |> __MODULE__.apply(new_stats)
      |> Equipment.sync_stats()
      |> Character.restore_health_and_mana()

    {character, level_delta(old_stats, new_stats)}
  end

  def apply(%Character{unit: %Unit{} = unit, player: %Player{} = player} = character, %__MODULE__{} = stats) do
    unit =
      unit
      |> Map.merge(power_fields(unit.class))
      |> Map.merge(%{
        level: stats.level,
        base_strength: stats.strength,
        base_agility: stats.agility,
        base_stamina: stats.stamina,
        base_intellect: stats.intellect,
        base_spirit: stats.spirit,
        base_mana: stats.base_mana,
        base_health: stats.base_health
      })
      |> StatsCore.recompute()

    player = %{
      player
      | next_level_xp: stats.next_level_xp,
        skills: Skills.on_level_up(player.skills, stats.level)
    }

    %{character | unit: unit, player: player}
    |> restart_level_played(character.unit.level, stats.level)
    |> CombatRatings.sync()
    |> SpellPower.recompute()
    |> Talents.sync_points(TalentLoader)
    |> Rest.set_bonus(character.internal.rest_bonus)
  end

  defp restart_level_played(character, level, level), do: character
  defp restart_level_played(character, _old_level, _new_level), do: PlayedTime.level_changed(character, Time.now())

  def level_delta(%__MODULE__{} = old, %__MODULE__{} = new) do
    %{
      new_level: new.level,
      health: max(new.max_health - old.max_health, 0),
      mana: max(new.max_mana - old.max_mana, 0),
      rage: 0,
      focus: 0,
      energy: 0,
      happiness: 0,
      strength: max(new.strength - old.strength, 0),
      agility: max(new.agility - old.agility, 0),
      stamina: max(new.stamina - old.stamina, 0),
      intellect: max(new.intellect - old.intellect, 0),
      spirit: max(new.spirit - old.spirit, 0)
    }
  end

  def from_character(%Character{unit: %Unit{} = unit, player: %Player{} = player}) do
    stats = %__MODULE__{
      race: unit.race,
      class: unit.class,
      level: unit.level,
      strength: unit.base_strength || unit.strength,
      agility: unit.base_agility || unit.agility,
      stamina: unit.base_stamina || unit.stamina,
      intellect: unit.base_intellect || unit.intellect,
      spirit: unit.base_spirit || unit.spirit,
      base_health: unit.base_health,
      base_mana: unit.base_mana,
      next_level_xp: player.next_level_xp
    }

    %{stats | max_health: max_health(stats), max_mana: max_mana(stats)}
  end

  defp build(%PlayerLevelStats{} = level_stats, %PlayerClassLevelStats{} = class_stats) do
    stats = %__MODULE__{
      race: level_stats.race,
      class: level_stats.class,
      level: level_stats.level,
      strength: level_stats.strength,
      agility: level_stats.agility,
      stamina: level_stats.stamina,
      intellect: level_stats.intellect,
      spirit: level_stats.spirit,
      base_health: class_stats.base_health,
      base_mana: class_stats.base_mana
    }

    %{
      stats
      | max_health: max_health(stats),
        max_mana: max_mana(stats),
        next_level_xp: next_level_xp(stats.level)
    }
  end

  defp max_health(%__MODULE__{base_health: base_health, stamina: stamina}) do
    base_health + stamina_health_bonus(stamina)
  end

  defp max_mana(%__MODULE__{base_mana: base_mana, intellect: intellect}) when base_mana > 0 do
    base_mana + mana_bonus(intellect)
  end

  defp max_mana(%__MODULE__{}), do: 0

  defdelegate melee_attack_power(class, level, strength, agility), to: StatsCore
  defdelegate ranged_attack_power(class, level, agility), to: StatsCore
  defdelegate stamina_health_bonus(stamina), to: StatsCore
  defdelegate mana_bonus(intellect), to: StatsCore

  defp power_fields(class) do
    %{
      max_power2: rage(class),
      max_power3: 0,
      max_power4: energy(class),
      max_power5: 0
    }
  end

  defp rage(1), do: 1000
  defp rage(_class), do: 0

  defp energy(4), do: 100
  defp energy(_class), do: 0
end
