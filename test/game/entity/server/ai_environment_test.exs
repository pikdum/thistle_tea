defmodule ThistleTea.Game.Entity.Server.AIEnvironmentTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "context/3" do
    test "captures an immutable observation of an explicit actor" do
      actor_guid = Guid.from_low_guid(:player, 98_001)
      world = %WorldRef{map_id: 0}

      SpatialHash.update(:players, actor_guid, world, 100.0, 0.0, 0.0)
      Metadata.put(actor_guid, %{alive?: true, level: 10})

      on_exit(fn ->
        SpatialHash.remove(:players, actor_guid)
        Metadata.delete(actor_guid)
      end)

      perception = AIEnvironment.context(mob(world), 1_000, Request.actor(actor_guid)).perception

      SpatialHash.update(:players, actor_guid, world, 200.0, 0.0, 0.0)
      Metadata.update(actor_guid, %{alive?: false, level: 20})

      assert Perception.position(perception, actor_guid) == {world, 100.0, 0.0, 0.0}
      assert Perception.distance(perception, actor_guid) == 100.0
      assert Perception.metadata(perception, actor_guid) == %{alive?: true, level: 10}
      assert Perception.nearby(perception, :players, 200.0) == []
    end

    test "expands the snapshot for behavior-declared observation ranges" do
      actor_guid = Guid.from_low_guid(:player, 98_003)
      world = %WorldRef{map_id: 0}
      event = %AIEvent{event_type: :friendly_hp, param2: 150}
      mob = mob(world)
      mob = %{mob | internal: %{mob.internal | creature: %Creature{ai_events: [event]}}}

      SpatialHash.update(:players, actor_guid, world, 100.0, 0.0, 0.0)
      Metadata.put(actor_guid, %{alive?: true})

      on_exit(fn ->
        SpatialHash.remove(:players, actor_guid)
        Metadata.delete(actor_guid)
      end)

      perception = AIEnvironment.context(mob, 1_000).perception

      assert Perception.nearby(perception, :players, 150.0) == [{actor_guid, 100.0}]
    end
  end

  defp mob(world) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 98_002)},
      unit: %Unit{target: 0, auras: []},
      internal: %Internal{world: world, threat: %{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
