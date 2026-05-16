defmodule ThistleTea.Game.Player.Stats do
  @moduledoc false

  alias ThistleTea.Character
  alias ThistleTea.DB.Mangos.PlayerClassLevelStats
  alias ThistleTea.DB.Mangos.PlayerLevelStats
  alias ThistleTea.DB.Mangos.PlayerXpForLevel
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit

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

  def apply(%Character{unit: %Unit{} = unit, player: %Player{} = player} = character, %__MODULE__{} = stats) do
    unit =
      unit
      |> Map.merge(power_fields(unit.class, stats))
      |> Map.merge(%{
        health: stats.max_health,
        max_health: stats.max_health,
        level: stats.level,
        strength: stats.strength,
        agility: stats.agility,
        stamina: stats.stamina,
        intellect: stats.intellect,
        spirit: stats.spirit,
        base_mana: stats.base_mana,
        base_health: stats.base_health
      })

    player = %{player | next_level_xp: stats.next_level_xp}
    %{character | unit: unit, player: player}
  end

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
    %__MODULE__{
      race: unit.race,
      class: unit.class,
      level: unit.level,
      strength: unit.strength,
      agility: unit.agility,
      stamina: unit.stamina,
      intellect: unit.intellect,
      spirit: unit.spirit,
      base_health: unit.base_health,
      base_mana: unit.base_mana,
      max_health: unit.max_health,
      max_mana: unit.max_power1,
      next_level_xp: player.next_level_xp
    }
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

  defp stamina_health_bonus(stamina) when stamina < 20, do: stamina
  defp stamina_health_bonus(stamina), do: 20 + (stamina - 20) * 10

  defp mana_bonus(intellect) when intellect < 20, do: intellect
  defp mana_bonus(intellect), do: 20 + (intellect - 20) * 15

  defp power_fields(class, %__MODULE__{} = stats) do
    %{
      power1: stats.max_mana,
      power2: 0,
      power3: 0,
      power4: energy(class),
      power5: 0,
      max_power1: stats.max_mana,
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
