defmodule ThistleTea.Game.Core.Condition.EntityContextTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Context, as: AIContext
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.EntityContext
  alias ThistleTea.Game.Core.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef

  describe "build/3" do
    test "projects observed player rank without inventing a missing fact" do
      guid = Guid.from_low_guid(:player, 123)
      observation = %Observation{guid: guid, metadata: %{honor_rank: 18}}
      perception = Perception.new(1_000, nil, %{guid => observation}, %{})
      ai_context = AIContext.new(1_000, perception: perception)
      context = EntityContext.build(mob(WorldRef.open(0)), ai_context, guid)
      condition = %Condition{type: :pvp_rank, value1: 14}
      assert Condition.evaluate(context, condition) == :met

      context = EntityContext.build(mob(WorldRef.open(0)), ai_context, guid + 1)
      assert {:unknown, _reasons} = Condition.evaluate(context, condition)
    end

    test "projects the boundary-supplied zone and area" do
      world = WorldRef.open(0)

      mob = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 1, 1), entry: 1},
        unit: %Unit{health: 100, max_health: 100, auras: []},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: world, area: 34, creature: %Creature{db_guid: 1}}
      }

      context = EntityContext.build(mob, AIContext.new(1_000, condition_area: {12, 34}))

      assert Condition.evaluate(context, %Condition{type: :area_id, value1: 12}) == :met
      assert Condition.evaluate(context, %Condition{type: :area_id, value1: 34}) == :met
      assert Condition.evaluate(context, %Condition{type: :area_id, value1: 56}) == :unmet
    end

    test "projects the source's unit and npc flags for has flag" do
      mob = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 1, 1), entry: 1},
        unit: %Unit{health: 100, max_health: 100, auras: [], flags: 0x200, npc_flags: 0x2},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0), creature: %Creature{db_guid: 1}}
      }

      context = EntityContext.build(mob, AIContext.new(1_000))

      assert Condition.evaluate(context, %Condition{type: :has_flag, value1: 147, value2: 0x2}) == :met
      assert Condition.evaluate(context, %Condition{type: :has_flag, value1: 46, value2: 0x200}) == :met
      assert Condition.evaluate(context, %Condition{type: :has_flag, value1: 46, value2: 0x100}) == :unmet
    end

    test "purely projects the boundary-supplied instance snapshot" do
      world = WorldRef.instance(329, 7)
      mob = mob(world)

      snapshot = %Snapshot{
        world: world,
        status: :available,
        script_name: "instance_stratholme",
        fields: %{7 => {:ok, 2}}
      }

      context = EntityContext.build(mob, AIContext.new(1_000, instance_data: snapshot))

      assert Condition.evaluate(context, %Condition{type: :instance_data, value1: 7, value2: 2}) == :met
    end
  end

  defp mob(world) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1), entry: 1},
      unit: %Unit{health: 100, max_health: 100, auras: []},
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
      internal: %Internal{world: world, area: 34, creature: %Creature{db_guid: 1}}
    }
  end
end
