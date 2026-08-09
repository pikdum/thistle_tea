defmodule ThistleTea.Game.InstanceScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.InstanceScript.Effects

  @stratholme "instance_stratholme"

  setup do
    {world, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)
    %{world: world, instances: instances}
  end

  describe "Baron encounter data" do
    test "closes the Baron gates in progress and opens them on failure", context do
      assert {:ok, 1, close_effects, instances} = Instance.command(context.instances, context.world, 5, 1, :raw)

      assert Enum.map(close_effects, &{&1.entry, &1.action}) == [
               {175_405, :close},
               {175_796, :close},
               {175_374, :close}
             ]

      assert {:ok, 2, open_effects, _instances} = Instance.command(instances, context.world, 5, 2, :raw)
      assert Enum.all?(open_effects, &match?(%Effects.OperateGameObject{action: :open}, &1))
    end

    test "starts the timed run once from the gauntlet gate", context do
      assert {:ok, effects, instances} = Instance.game_object_used(context.instances, context.world, 175_357)
      assert Instance.read(instances, context.world, 0) == {:ok, 1}

      assert [
               %Effects.SummonCreature{entry: 16_031},
               %Effects.MonsterTalk{creature_entry: 10_440, broadcast_text_id: 11_812},
               %Effects.CastPlayerSpell{spell_id: 27_861}
               | schedules
             ] = effects

      assert Enum.map(schedules, & &1.key) == [
               :baron_run_10_minutes,
               :baron_run_5_minutes,
               :baron_run_ysida,
               :baron_run_1_minute,
               :baron_run_expired
             ]

      assert {:ok, [], ^instances} = Instance.game_object_used(instances, context.world, 175_357)
    end

    test "completes the timed run atomically when Baron dies", context do
      {:ok, _effects, instances} = Instance.game_object_used(context.instances, context.world, 175_357)
      assert {:ok, 3, effects, instances} = Instance.command(instances, context.world, 5, 3, :raw)

      assert Instance.read(instances, context.world, 0) == {:ok, 3}
      assert Instance.read(instances, context.world, 5) == {:ok, 3}
      assert Enum.count(effects, &match?(%Effects.OperateGameObject{}, &1)) == 4
      assert Enum.any?(effects, &match?(%Effects.RemovePlayerAuras{}, &1))
      assert Enum.any?(effects, &match?(%Effects.QuestKillCredit{creature_entry: 16_031}, &1))
      assert Enum.any?(effects, &match?(%Effects.ModifyCreatureNpcFlags{creature_entry: 16_031}, &1))
      assert Enum.any?(effects, &match?(%Effects.MoveCreature{creature_entry: 16_031}, &1))
      assert Enum.any?(effects, &match?(%Effects.Schedule{key: :ysida_reward}, &1))
    end

    test "expires only an active timed run", context do
      {:ok, _effects, instances} = Instance.game_object_used(context.instances, context.world, 175_357)
      assert {:ok, effects, instances} = Instance.timer(instances, context.world, :baron_run_expired)

      assert Instance.read(instances, context.world, 0) == {:ok, 2}
      assert Enum.any?(effects, &match?(%Effects.TriggerCreatureSpell{creature_entry: 16_031, spell_id: 5}, &1))
      assert {:ok, [], ^instances} = Instance.timer(instances, context.world, :baron_run_expired)
    end

    test "emits milestone effects only while the run is active", context do
      assert {:ok, [], _instances} = Instance.timer(context.instances, context.world, :baron_run_10_minutes)
      {:ok, _effects, instances} = Instance.game_object_used(context.instances, context.world, 175_357)

      assert {:ok,
              [
                %Effects.MonsterTalk{broadcast_text_id: 11_813},
                %Effects.CastPlayerSpell{spell_id: 27_863}
              ], _instances} = Instance.timer(instances, context.world, :baron_run_10_minutes)
    end
  end
end
