defmodule ThistleTea.Game.Core.AI.BT.Context.CombatZone do
  @moduledoc "Dungeon membership observed for a creature's combat pulse. Actors live in the accompanying perception."

  @enforce_keys [:world]
  defstruct [:world, players: [], pets: %{}]

  def actors(nil), do: []
  def actors(%__MODULE__{players: players, pets: pets}), do: players ++ Map.values(pets)
end
