defmodule ThistleTea.Game.Core do
  @moduledoc """
  Pure game data and rules, grouped by domain: entities and their components,
  combat, spells, auras, items, quests, AI behavior trees, and the rest of the
  gameplay model. Core functions take data and return data; processes, ETS,
  the database, and packets belong to `ThistleTea.Game.World` and
  `ThistleTea.Game.Network`. Side effects leave core as `Core.Effects` structs
  for the owning world process to resolve. Where core must ask the world
  synchronously, it calls a port it defines (such as `Spell.TargetResolver`)
  that the world implements.
  """
  use Boundary, deps: [], exports: :all
end
