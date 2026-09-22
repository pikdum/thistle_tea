defmodule ThistleTea.Game.Entity.Logic.Wounded do
  @moduledoc """
  Creature health bands and the vanilla wounded running-speed penalty.
  Pets, world bosses, and templates opting out retain their normal speed.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureFlags

  def aura_state(%Mob{unit: unit}), do: elem(band(unit), 1)
  def aura_state(_entity), do: 0

  def speed_multiplier(%Mob{internal: %Internal{pet: %Pet{kind: kind}}}) when kind != :charmed, do: 1.0
  def speed_multiplier(%Mob{internal: %Internal{creature: %Creature{rank: 3}}}), do: 1.0

  def speed_multiplier(%Mob{unit: unit} = mob) do
    if CreatureFlags.no_wounded_slowdown?(mob), do: 1.0, else: elem(band(unit), 0)
  end

  def speed_multiplier(_entity), do: 1.0

  defp band(%Unit{health: health, max_health: maximum})
       when is_number(health) and health > 0 and is_number(maximum) and maximum > 0 do
    cond do
      health * 100 < maximum * 6 -> {0.5, 0x700}
      health * 100 < maximum * 11 -> {0.6, 0x300}
      health * 100 < maximum * 16 -> {0.7, 0x100}
      true -> {1.0, 0}
    end
  end

  defp band(_unit), do: {1.0, 0}
end
