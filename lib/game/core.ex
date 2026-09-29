defmodule ThistleTea.Game.Core do
  @moduledoc """
  Pure game data and rules, grouped by domain: entities and their components,
  combat, spells, auras, items, quests, AI behavior trees, and the rest of the
  gameplay model. Core functions take data and return data; processes, ETS,
  the database, and packets belong to `ThistleTea.Game.World` and
  `ThistleTea.Game.Network`. Side effects leave core as `Core.Effects` structs
  for the owning world process to resolve.

  `dirty_xrefs` lists the remaining references from core into the world and
  seed-database layers. It only shrinks.
  """
  use Boundary,
    deps: [],
    exports: :all,
    dirty_xrefs: [
      ThistleTea.DB.Mangos.GameEventGameObject,
      ThistleTea.DB.Mangos.GameObject,
      ThistleTea.DB.Mangos.GameObjectTemplate,
      ThistleTea.Game.World,
      ThistleTea.Game.World.Loader.Spell,
      ThistleTea.Game.World.Loader.Talent,
      ThistleTea.Game.World.Metadata,
      ThistleTea.Game.World.Spell.SpellTargetResolver,
      ThistleTea.Game.World.System.Duel
    ]
end
