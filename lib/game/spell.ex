defmodule ThistleTea.Game.Spell do
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Spell.Effect

  defstruct [
    :id,
    :name,
    :school,
    :cast_time_ms,
    :duration_ms,
    :range_yards,
    :mana_cost,
    :gcd_ms,
    attributes: MapSet.new(),
    effects: []
  ]

  def attribute?(%__MODULE__{attributes: attrs}, attr), do: MapSet.member?(attrs, attr)

  def school_mask(%__MODULE__{school: school}), do: school_mask(school)
  def school_mask(:physical), do: school_mask(0)
  def school_mask(:holy), do: school_mask(1)
  def school_mask(:fire), do: school_mask(2)
  def school_mask(:nature), do: school_mask(3)
  def school_mask(:frost), do: school_mask(4)
  def school_mask(:shadow), do: school_mask(5)
  def school_mask(:arcane), do: school_mask(6)
  def school_mask(school) when is_integer(school) and school >= 0, do: 1 <<< school
  def school_mask(_school), do: 0

  def aura_effects(%__MODULE__{effects: effects}) do
    Enum.filter(effects, &match?(%Effect{type: :apply_aura}, &1))
  end

  def damage_effects(%__MODULE__{effects: effects}) do
    Enum.filter(
      effects,
      &match?(%Effect{type: type} when type in [:school_damage, :weapon_damage, :weapon_damage_noschool], &1)
    )
  end

  def channel_tick_ms(%__MODULE__{effects: effects}) do
    effects
    |> Enum.map(& &1.amplitude_ms)
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.min(fn -> 1_000 end)
  end
end
