defmodule ThistleTea.Game.Core.AI.Script.MoveToTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.WorldRef

  setup [:mob]

  describe "Script.execute_steps/5" do
    test "target-relative coordinates retain authored offsets and movement options", %{mob: mob} do
      step = %ScriptStep{
        command: :move_to,
        datalong: 1,
        datalong2: 2_000,
        datalong3: 69,
        datalong4: 3,
        dataint: 7,
        position: {2.0, -3.0, 4.0, 1.2}
      }

      {moved, _} = Script.execute_steps(mob, Blackboard.new(), [step], 2, context(mob))
      assert [intent] = moved.internal.navigation_intents
      assert intent.destination == {12.0, -3.0, 9.0}
      assert intent.opts[:run?]
      assert intent.opts[:pathfind?]
      assert intent.opts[:travel_time] == 2_000
      assert intent.opts[:face_angle] == 1.2
      assert intent.opts[:movement_inform] == %Effects.MovementInform{motion_type: 9, point_id: 7}
    end

    test "distance mode measures from the target radius toward the source or an injected random angle", %{mob: mob} do
      for {orientation, expected, radius} <- [{-1.0, {7.5, 0.0, 5.0}, 0.5}, {0.0, {10.0, 2.389, 5.0}, nil}] do
        step = %ScriptStep{command: :move_to, datalong: 2, position: {2.0, 99.0, 99.0, orientation}}
        {moved, _} = Script.execute_steps(mob, Blackboard.new(), [step], 2, context(mob, radius))
        assert [intent] = moved.internal.navigation_intents
        {x, y, z} = intent.destination
        {ex, ey, ez} = expected
        assert_in_delta x, ex, 0.0001
        assert_in_delta y, ey, 0.0001
        assert z == ez
        refute Keyword.has_key?(intent.opts, :face_angle)
      end
    end

    test "missing and foreign targets, dead sources, and blocked movement honor abort", %{mob: mob} do
      step = %ScriptStep{command: :move_to, datalong: 1, position: {1.0, 0.0, 0.0, 0.0}}
      next = %ScriptStep{command: :set_phase, datalong: 7}
      dead = %{mob | unit: %{mob.unit | health: 0}}
      rooted = %{mob | movement_block: %{mob.movement_block | movement_flags: 0x08000000}}
      foreign = put_in(context(mob).perception.entities[2].position, {WorldRef.open(1), 10.0, 0.0, 5.0})

      for {source, context} <- [{mob, Context.new(0)}, {mob, foreign}, {dead, context(mob)}, {rooted, context(mob)}],
          abort? <- [true, false] do
        steps = [%{step | abort_on_failure?: abort?}, next]
        {unchanged, memory} = Script.execute_steps(source, Blackboard.new(), steps, 2, context)
        assert unchanged.internal.navigation_intents == []
        assert memory.event_ai.phase == if(abort?, do: 0, else: 7)
      end
    end
  end

  defp mob(_context) do
    %{
      mob: %Mob{
        object: %Object{guid: 3},
        unit: %Unit{health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 5.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }
    }
  end

  defp context(mob, radius \\ 0.5) do
    target = %Observation{guid: 2, position: {mob.internal.world, 10.0, 0.0, 5.0}, metadata: %{bounding_radius: radius}}
    perception = Perception.new(0, {mob.internal.world, 0.0, 0.0, 5.0}, %{2 => target}, %{})
    Context.new(0, perception: perception, random: Random.fixed(0.25))
  end
end
