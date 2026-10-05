defmodule ThistleTea.Game.Core.AI.BT.CasterChaseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.CasterChase
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:caster]

  describe "destination/2" do
    test "approaches a grounded target from the air while retaining the configured separation", %{mob: mob} do
      destination = CasterChase.destination(mob, {0.0, 0.0, 0.0})
      assert_in_delta Math.distance(destination, {0.0, 0.0, 0.0}), 25.0, 0.0001
      assert elem(destination, 2) > 0
      ground = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | script_flight: false}}}
      assert CasterChase.destination(ground, {0.0, 0.0, 0.0}) == {25.0, 0.0, 0.0}
    end
  end

  describe "hold_caster_distance/3" do
    test "holds and faces within range, but chases when the target moves or sight is blocked", %{
      mob: mob,
      target: target
    } do
      mob = %{mob | movement_block: %{mob.movement_block | position: {25.0, 0.0, 0.0, 0.0}}}
      mob = Movement.move_along_path(mob, [{0.0, 0.0, 0.0}], [run?: true], 0)
      assert Movement.moving?(mob, 0)
      observation = %Observation{guid: target, position: {mob.internal.world, 0.0, 0.0, 0.0}}
      context = context(mob, observation)
      assert CasterChase.in_range?(mob, context)
      assert {{:running, _, _}, held, _board} = MobBT.hold_caster_distance(mob, Blackboard.new(), context)
      refute Movement.moving?(held, 0)
      assert_in_delta elem(held.movement_block.position, 3), :math.pi(), 0.0001
      assert held.internal.navigation_intents == []

      for changed <- [
            %{observation | position: {mob.internal.world, -1.0, 0.0, 0.0}},
            %{observation | line_of_sight?: false},
            %{observation | position: {WorldRef.instance(30, Unique.integer()), 0.0, 0.0, 0.0}}
          ] do
        assert {:failure, ^mob, _board} = MobBT.hold_caster_distance(mob, Blackboard.new(), context(mob, changed))
      end
    end
  end

  describe "execute_steps/5" do
    test "the script override is cleared by respawn", %{mob: mob} do
      step = %ScriptStep{command: :set_caster_chase_distance, datalong: 30}
      {updated, _board} = Script.execute_steps(mob, Blackboard.new(), [step], mob.object.guid, 0)
      assert CasterChase.distance(updated) == 30
      assert CasterChase.distance(Mob.respawn(updated)) == nil
    end
  end

  defp context(mob, observation) do
    perception = Perception.new(0, mob.object.guid, %{observation.guid => observation}, %{})
    Context.new(0, perception: perception)
  end

  defp caster(_context) do
    target = Guid.from_low_guid(:player, Unique.integer())

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 14_943, Unique.integer())},
      unit: %Unit{health: 100, max_health: 100, target: target},
      movement_block: %MovementBlock{position: {40.0, 0.0, 30.0, 0.0}, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.instance(30, Unique.integer()),
        creature: %Creature{caster_chase_distance: 25, script_flight: true}
      }
    }

    %{mob: mob, target: target}
  end
end
