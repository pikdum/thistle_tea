defmodule ThistleTea.Game.Entity.Logic.Condition.EntityContextTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context, as: AIContext
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.EntityContext
  alias ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  describe "build/3" do
    test "projects the boundary-supplied zone and area" do
      world = WorldRef.open(0)

      mob = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 1, 1), entry: 1},
        unit: %Unit{health: 100, max_health: 100, auras: []},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: world, area: 34, creature: %Creature{db_guid: 1}}
      }

      context = EntityContext.build(mob, AIContext.new(1_000, condition_area: {12, 34}))

      assert Evaluator.evaluate(context, %Condition{type: :area_id, value1: 12}) == :met
      assert Evaluator.evaluate(context, %Condition{type: :area_id, value1: 34}) == :met
      assert Evaluator.evaluate(context, %Condition{type: :area_id, value1: 56}) == :unmet
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

      assert Evaluator.evaluate(context, %Condition{type: :instance_data, value1: 7, value2: 2}) == :met
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
