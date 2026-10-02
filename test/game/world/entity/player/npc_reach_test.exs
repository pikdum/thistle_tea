defmodule ThistleTea.Game.World.Entity.Player.NpcReachTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.NpcReach
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  setup do
    creature = Guid.from_low_guid(:mob, 9_459, Unique.integer())
    Metadata.put(creature, %{bounding_radius: 2.83})

    on_exit(fn ->
      Metadata.delete(creature)
      SpatialHash.remove(:mobs, creature)
    end)

    %{character: character(0.208), creature: creature}
  end

  describe "within?/2" do
    test "reaches five yards past both bodies", %{character: character, creature: creature} do
      SpatialHash.update(:mobs, creature, WorldRef.open(0), 8.0, 0.0, 0.0)
      assert NpcReach.within?(character, creature)

      SpatialHash.update(:mobs, creature, WorldRef.open(0), 8.1, 0.0, 0.0)
      refute NpcReach.within?(character, creature)
    end

    test "measures from centers when neither radius is known", %{creature: creature} do
      Metadata.delete(creature)
      character = character(nil)

      SpatialHash.update(:mobs, creature, WorldRef.open(0), 5.0, 0.0, 0.0)
      assert NpcReach.within?(character, creature)

      SpatialHash.update(:mobs, creature, WorldRef.open(0), 5.01, 0.0, 0.0)
      refute NpcReach.within?(character, creature)
    end

    test "never reaches a creature in another world", %{character: character, creature: creature} do
      SpatialHash.update(:mobs, creature, WorldRef.open(1), 1.0, 0.0, 0.0)

      refute NpcReach.within?(character, creature)
    end
  end

  defp character(bounding_radius) do
    id = Unique.integer()

    %Character{
      id: id,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      unit: %Unit{bounding_radius: bounding_radius},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end
end
