defmodule ThistleTea.Game.World.InstanceSpawnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.InstanceSpawn
  alias ThistleTea.Game.WorldRef

  describe "materialize/2" do
    test "allocates distinct runtime guids while preserving database identity" do
      db_guid = 42
      blueprint = mob(db_guid)
      first = InstanceSpawn.materialize(blueprint, WorldRef.instance(389, 1))
      second = InstanceSpawn.materialize(blueprint, WorldRef.instance(389, 2))

      refute first.object.guid == second.object.guid
      assert first.internal.creature.db_guid == db_guid
      assert second.internal.creature.db_guid == db_guid
      assert first.internal.world == WorldRef.instance(389, 1)
      assert second.internal.world == WorldRef.instance(389, 2)
    end

    test "retains database guids in the open world" do
      blueprint = mob(42)
      materialized = InstanceSpawn.materialize(blueprint, WorldRef.open(389))

      assert materialized.object.guid == blueprint.object.guid
    end
  end

  defp mob(db_guid) do
    unit = %Unit{auras: []}

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 113, db_guid), entry: 113},
      unit: unit,
      internal: %Internal{creature: %Creature{db_guid: db_guid}, spawn: %Spawn{unit: unit}}
    }
  end
end
