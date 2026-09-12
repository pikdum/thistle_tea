defmodule ThistleTea.Game.InstanceDeadminesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.InstanceScript.Effects

  setup [:dungeon]

  describe "creature_event/3" do
    test "opens each boss door once and restores it when reloaded", context do
      for {boss, door} <- [{644, 13_965}, {643, 16_400}, {1_763, 16_399}] do
        event = %{creature_entry: boss, event: :death}
        effect = %Effects.OperateGameObject{entry: door, action: :open}

        assert {:ok, [^effect], instances} = Instance.creature_event(context.instances, context.world, event)
        assert {:ok, [], ^instances} = Instance.creature_event(instances, context.world, event)
        assert {:ok, [^effect], ^instances} = Instance.game_object_spawned(instances, context.world, door)
      end
    end

    test "does not open Sneed's door when only the shredder dies", context do
      assert {:ok, [], _} =
               Instance.creature_event(context.instances, context.world, %{creature_entry: 642, event: :death})
    end
  end

  describe "game_object_used/3" do
    test "collecting gunpowder summons a single approaching overseer", context do
      assert {:ok, [%Effects.SummonCreature{entry: 634, move_to: {_, _, _}}], instances} =
               Instance.game_object_used(context.instances, context.world, 17_155)

      assert {:ok, [], ^instances} = Instance.game_object_used(instances, context.world, 17_155)
    end

    test "breaches the door and schedules one alarm per copy", context do
      assert {:ok,
              [
                %Effects.OperateGameObject{entry: 16_398, action: :open},
                %Effects.OperateGameObject{entry: 16_397, action: :destroy},
                %Effects.Schedule{key: :deadmines_alarm, delay_ms: 3_000}
              ], instances} = Instance.game_object_used(context.instances, context.world, 16_398)

      assert {:ok, [], ^instances} = Instance.game_object_used(instances, context.world, 16_398)

      assert {:ok, [%Effects.OperateGameObject{action: :destroy}], ^instances} =
               Instance.game_object_spawned(instances, context.world, 16_397)

      {other, nil, instances} = Instance.enter(instances, 36, {:player, 200}, 200, "instance_deadmines")
      assert Instance.read(instances, other, 1) == {:ok, 0}
      assert {:ok, [], ^instances} = Instance.game_object_spawned(instances, other, 16_397)
      assert {:ok, [_cannon, _door, _timer], _instances} = Instance.game_object_used(instances, other, 16_398)
    end
  end

  describe "timer/3" do
    test "runs both alarm stages in order without replaying stale timers", context do
      assert {:ok, [], _} = Instance.timer(context.instances, context.world, :deadmines_alarm)
      {:ok, _, instances} = Instance.game_object_used(context.instances, context.world, 16_398)
      assert {:ok, [], ^instances} = Instance.timer(instances, context.world, :deadmines_attack)

      assert {:ok,
              [
                %Effects.MonsterTalk{broadcast_text_id: 1_148},
                %Effects.MoveCreature{creature_db_guid: 79_289},
                %Effects.MoveCreature{creature_db_guid: 79_290},
                %Effects.Schedule{key: :deadmines_attack, delay_ms: 15_000}
              ], instances} = Instance.timer(instances, context.world, :deadmines_alarm)

      assert {:ok, [], ^instances} = Instance.timer(instances, context.world, :deadmines_alarm)

      assert {:ok, [%Effects.MonsterTalk{broadcast_text_id: 1_149}], instances} =
               Instance.timer(instances, context.world, :deadmines_attack)

      assert {:ok, [], ^instances} = Instance.timer(instances, context.world, :deadmines_attack)
      assert Instance.read(instances, context.world, 1) == {:ok, 3}

      assert {:ok, [%Effects.MoveCreature{creature_db_guid: 79_289}], _} =
               Instance.creature_event(instances, context.world, %{
                 creature_entry: 657,
                 db_guid: 79_289,
                 event: :spawned
               })

      assert {:ok, [], _} =
               Instance.creature_event(instances, context.world, %{creature_entry: 657, db_guid: 1, event: :spawned})
    end
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 36, {:player, 100}, 100, "instance_deadmines")
    %{world: world, instances: instances}
  end
end
