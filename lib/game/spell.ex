defmodule ThistleTea.Game.Spell do
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

  def aura_effects(%__MODULE__{effects: effects}) do
    Enum.filter(effects, &match?(%Effect{type: :apply_aura}, &1))
  end

  def damage_effects(%__MODULE__{effects: effects}) do
    Enum.filter(effects, &match?(%Effect{type: type} when type in [:school_damage, :weapon_damage], &1))
  end

  def channel_tick_ms(%__MODULE__{effects: effects}) do
    effects
    |> Enum.map(& &1.amplitude_ms)
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.min(fn -> 1_000 end)
  end
end
