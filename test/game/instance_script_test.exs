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

  describe "undead-side progression" do
    test "opens each ziggurat when its boss dies", context do
      bosses = [{10_436, 1, 175_380}, {10_437, 2, 175_379}, {10_438, 3, 175_381}]

      instances =
        Enum.reduce(bosses, context.instances, fn {entry, field, door}, instances ->
          assert {:ok, [%Effects.OperateGameObject{entry: ^door, action: :open}], instances} =
                   Instance.creature_event(instances, context.world, creature_event(entry, :death))

          assert Instance.read(instances, context.world, field) == {:ok, 3}
          instances
        end)

      assert Instance.read(instances, context.world, 1) == {:ok, 3}
      assert Instance.read(instances, context.world, 2) == {:ok, 3}
      assert Instance.read(instances, context.world, 3) == {:ok, 3}
    end

    test "topples each crystal from its five exact acolyte spawns", context do
      groups = [
        {53_955, [53_268, 53_269, 53_270, 53_271, 53_272]},
        {53_963, [53_257, 53_258, 53_259, 53_260, 53_261]},
        {53_968, [53_262, 53_263, 53_264, 53_265, 53_266]}
      ]

      {instances, crystal_effects} =
        Enum.reduce(groups, {context.instances, []}, fn {crystal_db_guid, acolyte_guids}, {instances, effects} ->
          {instances, group_effects} = kill_group(instances, context.world, acolyte_guids)

          assert [%Effects.TriggerCreatureSpell{creature_db_guid: ^crystal_db_guid, spell_id: 5}] = group_effects
          {instances, effects ++ group_effects}
        end)

      assert length(crystal_effects) == 3

      {instances, first_effects} = kill_crystal(instances, context.world, 53_955, 101)
      assert [%Effects.MonsterTalk{broadcast_text_id: 6_527}] = first_effects
      {instances, _second_effects} = kill_crystal(instances, context.world, 53_963, 102)
      {instances, final_effects} = kill_crystal(instances, context.world, 53_968, 103)

      assert Instance.read(instances, context.world, 6) == {:ok, 3}
      assert Enum.any?(final_effects, &match?(%Effects.OperateGameObject{entry: 175_374, action: :open}, &1))
      assert Enum.any?(final_effects, &match?(%Effects.OperateGameObject{entry: 175_373, action: :open}, &1))
      assert Enum.any?(final_effects, &match?(%Effects.MonsterTalk{broadcast_text_id: 6_289}, &1))

      assert {:ok, [], _instances} =
               Instance.creature_event(
                 instances,
                 context.world,
                 creature_event(10_415, :death, db_guid: 53_968, guid: 103)
               )
    end

    test "moves abomination waves and summons Ramstein exactly once", context do
      abominations = [
        {53_969, 10_416},
        {54_002, 10_416},
        {54_018, 10_416},
        {54_019, 10_416},
        {54_020, 10_417},
        {54_021, 10_417},
        {54_022, 10_417},
        {54_026, 10_417},
        {54_027, 10_417},
        {54_039, 10_417},
        {54_040, 10_417},
        {54_041, 10_417},
        {54_050, 10_417}
      ]

      instances =
        Enum.reduce(abominations, context.instances, fn {db_guid, entry}, instances ->
          guid = 100_000 + db_guid

          assert {:ok, [], instances} =
                   Instance.creature_event(
                     instances,
                     context.world,
                     creature_event(entry, :spawned, db_guid: db_guid, guid: guid)
                   )

          instances
        end)

      assert {:ok, 4, special_effects, instances} = Instance.command(instances, context.world, 4, 4, :raw)
      assert Enum.any?(special_effects, &match?(%Effects.Schedule{key: :abomination_wave, delay_ms: 20_000}, &1))
      assert {:ok, wave_effects, instances} = Instance.timer(instances, context.world, :abomination_wave)
      assert Enum.any?(wave_effects, &match?(%Effects.MoveCreature{creature_guid: guid} when is_integer(guid), &1))

      {instances, final_effects} =
        Enum.reduce(abominations, {instances, []}, fn {db_guid, entry}, {instances, _effects} ->
          guid = 100_000 + db_guid

          assert {:ok, effects, instances} =
                   Instance.creature_event(
                     instances,
                     context.world,
                     creature_event(entry, :death, db_guid: db_guid, guid: guid)
                   )

          {instances, effects}
        end)

      assert Instance.read(instances, context.world, 4) == {:ok, 1}
      assert Instance.read(instances, context.world, 8) == {:ok, 3}
      assert Enum.any?(final_effects, &match?(%Effects.MonsterTalk{broadcast_text_id: 6_398}, &1))

      assert Enum.any?(final_effects, fn
               %Effects.SummonCreature{entry: 10_439, move_to: {4_033.009, -3_404.3293, 115.3554}} -> true
               _effect -> false
             end)

      assert {:ok, [], _instances} =
               Instance.creature_event(
                 instances,
                 context.world,
                 creature_event(10_417, :death, db_guid: 54_050, guid: 154_050)
               )
    end

    test "runs the Ramstein aftermath and unlocks Baron", context do
      assert {:ok, [%Effects.ModifyCreatureUnitFlags{mode: :add}], instances} =
               Instance.creature_event(context.instances, context.world, creature_event(10_440, :spawned))

      assert {:ok, [%Effects.OperateGameObject{entry: 175_374, action: :close}], instances} =
               Instance.creature_event(instances, context.world, creature_event(10_439, :aggro))

      assert Instance.read(instances, context.world, 4) == {:ok, 1}

      assert {:ok, effects, instances} =
               Instance.creature_event(instances, context.world, creature_event(10_439, :death))

      assert Instance.read(instances, context.world, 4) == {:ok, 3}
      assert Enum.count(effects, &match?(%Effects.SummonCreature{entry: 11_030}, &1)) == 34
      assert Enum.any?(effects, &match?(%Effects.Schedule{key: :black_guard_assault, delay_ms: 60_000}, &1))
      assert Enum.any?(effects, &match?(%Effects.Schedule{key: :slaughter_square_gate_reset}, &1))

      assert {:ok, guard_effects, instances} = Instance.timer(instances, context.world, :black_guard_assault)
      assert Enum.count(guard_effects, &match?(%Effects.SummonCreature{entry: 10_394}, &1)) == 5
      assert Enum.any?(guard_effects, &match?(%Effects.ModifyCreatureUnitFlags{mode: :remove}, &1))

      assert {:ok, [%Effects.MonsterTalk{broadcast_text_id: 6_415, creature_guid: 201}], instances} =
               Instance.creature_event(instances, context.world, creature_event(10_394, :spawned, guid: 201))

      assert {:ok, [], instances} =
               Instance.creature_event(instances, context.world, creature_event(10_394, :spawned, guid: 202))

      {instances, ready_effects} =
        Enum.reduce(201..205, {instances, []}, fn guid, {instances, _effects} ->
          assert {:ok, effects, instances} =
                   Instance.creature_event(instances, context.world, creature_event(10_394, :death, guid: guid))

          {instances, effects}
        end)

      assert [%Effects.MonsterTalk{creature_entry: 10_440, broadcast_text_id: 6_401}] = ready_effects

      assert {:ok, [], _instances} =
               Instance.creature_event(instances, context.world, creature_event(10_394, :death, guid: 205))
    end
  end

  defp kill_group(instances, world, acolyte_guids) do
    Enum.reduce(acolyte_guids, {instances, []}, fn db_guid, {instances, _effects} ->
      assert {:ok, effects, instances} =
               Instance.creature_event(
                 instances,
                 world,
                 creature_event(10_399, :death, db_guid: db_guid, guid: 100_000 + db_guid)
               )

      {instances, effects}
    end)
  end

  defp kill_crystal(instances, world, db_guid, guid) do
    assert {:ok, effects, instances} =
             Instance.creature_event(instances, world, creature_event(10_415, :death, db_guid: db_guid, guid: guid))

    {instances, effects}
  end

  defp creature_event(entry, event, options \\ []) do
    %{
      creature_entry: entry,
      creature_guid: Keyword.get(options, :guid, entry * 10),
      db_guid: Keyword.get(options, :db_guid),
      event: event
    }
  end
end
