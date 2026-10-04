defmodule ThistleTea.Game.World.Entity.Player.ObjectRequirementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameObject.UseRequirement
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.ObjectRequirement
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  @relic_coffer 160_836
  @coffer_door 160_840

  setup do
    world = WorldRef.instance(230, Unique.integer())
    coffer = Guid.from_low_guid(:game_object, @relic_coffer, Unique.integer())
    door = Guid.from_low_guid(:game_object, @coffer_door, Unique.integer())
    door_db_guid = Unique.integer()
    coffer_db_guid = Unique.integer()

    Metadata.put(coffer, %{db_guid: coffer_db_guid})
    place(door, world, %{db_guid: door_db_guid, go_state: 1})

    on_exit(fn -> Metadata.delete(coffer) end)

    requirements = fn
      ^coffer_db_guid -> UseRequirement.from_row(1, door_db_guid)
      _other -> nil
    end

    %{world: world, coffer: coffer, door: door, requirements: requirements}
  end

  describe "met?/3" do
    test "keeps a coffer shut until its door in the same copy opens", context do
      refute ObjectRequirement.met?(context.world, context.coffer, context.requirements)
      assert ObjectRequirement.met?(WorldRef.instance(230, Unique.integer()), context.coffer, context.requirements)

      Metadata.update(context.door, %{go_state: 0})
      assert ObjectRequirement.met?(context.world, context.coffer, context.requirements)
    end

    test "lets anything without a requirement be used", context do
      assert ObjectRequirement.met?(context.world, context.door, context.requirements)
    end
  end

  defp place(guid, world, metadata) do
    Metadata.put(guid, metadata)
    SpatialHash.update(:game_objects, guid, world, 0.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(guid)
      SpatialHash.remove(:game_objects, guid)
    end)
  end
end
