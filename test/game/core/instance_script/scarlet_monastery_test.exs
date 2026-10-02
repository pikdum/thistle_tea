defmodule ThistleTea.Game.Core.InstanceScript.ScarletMonasteryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @mograine 3_976
  @whitemane 3_977
  @door 104_600

  setup [:cathedral]

  describe "InstanceScript.data64/2" do
    test "names Mograine and Whitemane's spawns" do
      assert InstanceScript.data64("instance_scarlet_monastery", 2) == 40_029
      assert InstanceScript.data64("instance_scarlet_monastery", 3) == 39_946
      assert InstanceScript.data64("instance_scarlet_monastery", 4) == nil
      assert InstanceScript.data64("instance_deadmines", 2) == nil
      assert InstanceScript.data64(nil, 2) == nil
    end
  end

  describe "set_data/3" do
    test "Mograine's fall opens the door and sends Whitemane to raise him", context do
      assert {:ok, 1, defenders, instances} = stage(context.instances, context, 1)
      assert Enum.map(defenders, & &1.creature_entry) == [4_299, 4_300, 4_301, 4_302, 4_303, 4_540]

      for defender <- defenders do
        assert %Effects.RunCreatureScript{within: {{_x, _y, _z}, 82.0}, steps: [pulse]} = defender
        assert %ScriptStep{command: :zone_combat_pulse} = pulse
      end

      assert {:ok, 2, [open, yell, run], instances} = stage(instances, context, 2)
      assert open == %Effects.OperateGameObject{entry: @door, action: :open}
      assert yell == %Effects.MonsterTalk{creature_entry: @whitemane, broadcast_text_id: 2_973}
      assert %Effects.RunCreatureScript{creature_entry: @whitemane, steps: [move]} = run

      assert %ScriptStep{
               command: :move_to,
               target_type: :creature_from_instance_data,
               target_param1: 2,
               dataint: 100
             } = move

      assert {:ok, 3, [mograine, whitemane], instances} = stage(instances, context, 3)
      assert [@mograine, @whitemane] == Enum.map([mograine, whitemane], & &1.creature_entry)
      assert [%ScriptStep{command: :zone_combat_pulse}] = mograine.steps
      assert {:ok, [^open], _} = Instance.game_object_spawned(instances, context.world, @door)
    end

    test "a wipe before anyone dies shuts the door and sends Whitemane home", context do
      {:ok, _stored, _effects, instances} = stage(context.instances, context, 1)
      {:ok, _stored, _effects, instances} = stage(instances, context, 2)

      assert {:ok, 0, [close, reset], instances} = stage(instances, context, 0)
      assert close == %Effects.OperateGameObject{entry: @door, action: :close}

      assert %Effects.RunCreatureScript{creature_entry: @whitemane, steps: [%ScriptStep{command: :respawn_creature}]} =
               reset

      assert {:ok, [], _} = Instance.game_object_spawned(instances, context.world, @door)
    end

    test "a wipe after one of them died removes the survivor and settles the fight", context do
      {:ok, _stored, _effects, instances} = stage(context.instances, context, 3)
      {:ok, [], instances} = death(instances, context, @mograine)

      assert {:ok, 4, [despawn], instances} = stage(instances, context, 0)
      assert %Effects.RunCreatureScript{creature_entry: @whitemane, steps: [%ScriptStep{command: :despawn}]} = despawn
      assert {:ok, 4, [], instances} = stage(instances, context, 1)

      spawned = %{creature_entry: @whitemane, event: :spawned}

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: @whitemane}], _} =
               Instance.creature_event(instances, context.world, spawned)
    end
  end

  describe "creature_event/3" do
    test "both deaths settle the encounter with the door open", context do
      {:ok, _stored, _effects, instances} = stage(context.instances, context, 3)
      assert {:ok, [], instances} = death(instances, context, @whitemane)
      assert {:ok, [], instances} = death(instances, context, @whitemane)
      assert {:ok, [], instances} = death(instances, context, @mograine)
      assert Instance.read(instances, context.world, 1) == {:ok, 4}
    end

    test "a dead Whitemane neither yells nor runs when Mograine falls", context do
      {:ok, [], instances} = death(context.instances, context, @whitemane)
      assert {:ok, 2, [%Effects.OperateGameObject{entry: @door, action: :open}], _} = stage(instances, context, 2)
    end

    test "a boss that spawns again is no longer counted dead", context do
      {:ok, [], instances} = death(context.instances, context, @mograine)

      {:ok, [], instances} =
        Instance.creature_event(instances, context.world, %{creature_entry: @mograine, event: :spawned})

      assert {:ok, 0, [], _} = stage(instances, context, 0)
    end
  end

  defp stage(instances, context, value), do: Instance.command(instances, context.world, 1, value, :raw)

  defp death(instances, context, entry),
    do: Instance.creature_event(instances, context.world, %{creature_entry: entry, event: :death})

  defp cathedral(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 189, {:player, 100}, 100, "instance_scarlet_monastery")
    %{world: world, instances: instances}
  end
end
