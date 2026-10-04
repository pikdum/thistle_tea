defmodule ThistleTea.Game.Core.InstanceScript.UldamanTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @archaedas 2_748
  @stone_keeper 4_857
  @earthen_guardian 7_076
  @earthen_custodian 7_309
  @ironaya 7_228
  @vault_warder 10_120

  @keystone 124_371
  @seal_of_khazmul 124_372
  @keepers_temple_door 124_367
  @ancient_vault 124_369
  @archaedas_temple_door 141_869

  setup [:dungeon]

  describe "InstanceScript.scripted_door?/2" do
    test "keeps players' hands off the doors Uldaman opens itself" do
      for door <- [@seal_of_khazmul, @keepers_temple_door, @ancient_vault, @archaedas_temple_door] do
        assert InstanceScript.scripted_door?("instance_uldaman", door)
      end

      refute InstanceScript.scripted_door?("instance_uldaman", @keystone)
    end
  end

  describe "the Keystone" do
    test "opens the Seal of Khaz'Mul half a minute later and wakes Ironaya", context do
      {instances, _effects} = spawned(context, @ironaya, 1, 54_080)

      assert {:ok, [%Effects.Schedule{key: :seal_opens, delay_ms: 27_000}], instances} =
               Instance.game_object_used(instances, context.world, @keystone)

      assert {:ok, [], instances} = Instance.game_object_used(instances, context.world, @keystone)
      assert {:ok, [], _} = Instance.game_object_spawned(instances, context.world, @seal_of_khazmul)

      assert {:ok, [%Effects.OperateGameObject{entry: @seal_of_khazmul, action: :open}, wake], instances} =
               Instance.timer(instances, context.world, :seal_opens)

      assert %Effects.RunCreatureScript{creature_entry: @ironaya, steps: steps} = wake
      assert %ScriptStep{command: :set_faction, datalong: 415} = Enum.find(steps, &(&1.command == :set_faction))
      assert %ScriptStep{command: :attack_start, target_param1: 80} = List.last(steps)
      assert Instance.read(instances, context.world, 0) == {:ok, 3}

      assert {:ok, [%Effects.OperateGameObject{action: :open}], _} =
               Instance.game_object_spawned(instances, context.world, @seal_of_khazmul)
    end

    test "Ironaya stands as stone until the seal has opened", context do
      {_instances, [freeze]} = spawned(context, @ironaya, 1, 54_080)

      assert %Effects.RunCreatureScript{creature_guid: 1, steps: [flags, stoned]} = freeze
      assert %ScriptStep{command: :modify_flags, datalong2: 0x02000300, datalong3: 1} = flags
      assert %ScriptStep{command: :cast_spell, datalong: 10_255} = stoned
    end
  end

  describe "the Stone Keepers" do
    test "wake one at a time and open the temple door once all have fallen", context do
      {instances, _effects} = spawned(context, @stone_keeper, [{11, 28_368}, {12, 27_555}])

      assert {:ok, 1, [%Effects.Schedule{key: :wake_keeper}], instances} = start(instances, context, 1)
      assert {:ok, [wake], instances} = Instance.timer(instances, context.world, :wake_keeper)
      assert %Effects.RunCreatureScript{creature_guid: 12, steps: steps} = wake
      assert %ScriptStep{command: :set_faction, datalong: 470} = Enum.find(steps, &(&1.command == :set_faction))

      assert {:ok, [], instances} = Instance.timer(instances, context.world, :wake_keeper)

      {:ok, [%Effects.Schedule{key: :wake_keeper}], instances} = die(instances, context, @stone_keeper, 12)

      assert {:ok, [%Effects.RunCreatureScript{creature_guid: 11}], instances} =
               Instance.timer(instances, context.world, :wake_keeper)

      {:ok, _effects, instances} = die(instances, context, @stone_keeper, 11)

      assert {:ok, [%Effects.OperateGameObject{entry: @keepers_temple_door, action: :open}], instances} =
               Instance.timer(instances, context.world, :wake_keeper)

      assert Instance.read(instances, context.world, 1) == {:ok, 3}
    end

    test "turn back to stone when the awake one gives up its fight", context do
      {instances, _effects} = spawned(context, @stone_keeper, [{11, 28_368}, {12, 27_555}])
      {:ok, 1, _effects, instances} = start(instances, context, 1)
      {:ok, _wake, instances} = Instance.timer(instances, context.world, :wake_keeper)
      {:ok, _effects, instances} = die(instances, context, @stone_keeper, 12)
      {:ok, _wake, instances} = Instance.timer(instances, context.world, :wake_keeper)

      assert {:ok, effects, instances} =
               Instance.creature_event(instances, context.world, event(@stone_keeper, 11, :evade))

      assert Enum.sort(for %Effects.RunCreatureScript{creature_guid: guid} <- effects, do: guid) == [11, 12]
      assert Instance.read(instances, context.world, 1) == {:ok, 2}
    end
  end

  describe "Archaedas" do
    test "wakes at his altar and shuts the temple door behind his challengers", context do
      assert {:ok, 1, effects, instances} = start(context.instances, context, 2)

      assert %Effects.MonsterTalk{creature_entry: @archaedas, broadcast_text_id: 3_400} in effects
      assert %Effects.RunCreatureScript{creature_entry: @archaedas, steps: [awaken | _]} = Enum.at(effects, 0)
      assert %ScriptStep{command: :cast_spell, datalong: 10_347} = awaken
      assert Instance.read(instances, context.world, 11) == {:ok, 1}

      assert {:ok, 1, [%Effects.Schedule{key: :wake_wall_minion}], _} = start(instances, context, 2)
    end

    test "wakes the earliest earthen on the wall every time his fight asks", context do
      {instances, _effects} = spawned(context, @earthen_custodian, [{21, 33_557}, {22, 33_541}])
      {:ok, 1, _effects, instances} = start(instances, context, 2)

      assert {:ok, [cast, wake], instances} = Instance.timer(instances, context.world, :wake_wall_minion)
      assert %Effects.RunCreatureScript{creature_entry: @archaedas, steps: [%ScriptStep{buddy_guid: 22}]} = cast
      assert %Effects.RunCreatureScript{creature_guid: 22, steps: steps} = wake
      assert %ScriptStep{command: :attack_start, delay_ms: 4_000} = List.last(steps)

      assert {:ok, [_cast, %Effects.RunCreatureScript{creature_guid: 21}], instances} =
               Instance.timer(instances, context.world, :wake_wall_minion)

      assert {:ok, [], _} = Instance.timer(instances, context.world, :wake_wall_minion)
    end

    test "calls the guardians and the chamber's warders, and sends the outer warders away", context do
      {instances, _effects} = spawned(context, @earthen_guardian, [{31, 33_586}, {32, 33_551}])
      {instances, _effects} = spawned(%{context | instances: instances}, @vault_warder, [{41, 33_549}, {42, 33_504}])
      {:ok, 1, _effects, instances} = start(instances, context, 2)

      assert {:ok, 1, [%Effects.Schedule{key: 13}], instances} = Instance.command(instances, context.world, 13, 1, :raw)
      assert {:ok, 1, [], instances} = Instance.command(instances, context.world, 13, 1, :raw)
      assert {:ok, wakes, instances} = Instance.timer(instances, context.world, 13)
      assert Enum.map(wakes, & &1.creature_guid) == [32, 31]

      {:ok, 1, _effects, instances} = Instance.command(instances, context.world, 14, 1, :raw)
      assert {:ok, [despawn, wake], _} = Instance.timer(instances, context.world, 14)
      assert %Effects.RunCreatureScript{creature_guid: 42, steps: [%ScriptStep{command: :despawn}]} = despawn
      assert %Effects.RunCreatureScript{creature_guid: 41, steps: steps} = wake
      assert %ScriptStep{command: :set_faction, datalong: 415} = Enum.find(steps, &(&1.command == :set_faction))
    end

    test "opens the temple door when he gives up and puts his chamber back to sleep at home", context do
      {instances, _effects} = spawned(context, @earthen_custodian, [{21, 33_557}])
      {instances, _effects} = spawned(%{context | instances: instances}, @archaedas, [{1, 33_537}])
      {:ok, 1, _effects, instances} = start(instances, context, 2)
      {:ok, _effects, instances} = Instance.timer(instances, context.world, :wake_wall_minion)

      assert {:ok, [%Effects.OperateGameObject{entry: @archaedas_temple_door, action: :open}], instances} =
               Instance.creature_event(instances, context.world, event(@archaedas, 1, :evade))

      assert {:ok, 0, [%Effects.Schedule{key: :reset_chamber}], instances} =
               Instance.command(instances, context.world, 2, 0, :raw)

      assert {:ok, [%Effects.RunCreatureScript{creature_guid: 21, steps: [respawn]}], instances} =
               Instance.timer(instances, context.world, :reset_chamber)

      assert %ScriptStep{command: :respawn_creature, datalong: 1} = respawn
      assert {:ok, [_cast, %Effects.RunCreatureScript{creature_guid: 21}], _} = wake_again(instances, context)
    end

    test "his death opens the vault and crumbles the earthen still standing", context do
      {instances, _effects} = spawned(context, @earthen_custodian, [{21, 33_557}])
      {instances, _effects} = spawned(%{context | instances: instances}, @archaedas, [{1, 33_537}])
      {:ok, 1, _effects, instances} = start(instances, context, 2)

      assert {:ok, effects, instances} = die(instances, context, @archaedas, 1)
      assert opened(effects) == [@ancient_vault, @archaedas_temple_door]
      assert %Effects.Schedule{key: :clear_chamber, delay_ms: 0} in effects

      assert {:ok, [%Effects.RunCreatureScript{creature_guid: 21, steps: [despawn]}], instances} =
               Instance.timer(instances, context.world, :clear_chamber)

      assert %ScriptStep{command: :despawn} = despawn

      assert {:ok, 3, [], _} = start(instances, context, 2)
    end
  end

  defp wake_again(instances, context) do
    {:ok, 1, _effects, instances} = start(instances, context, 2)
    Instance.timer(instances, context.world, :wake_wall_minion)
  end

  defp spawned(context, entry, guid, db_guid), do: spawned(context, entry, [{guid, db_guid}])

  defp spawned(context, entry, creatures) do
    Enum.reduce(creatures, {context.instances, []}, fn {guid, db_guid}, {instances, _effects} ->
      event = %{event(entry, guid, :spawned) | db_guid: db_guid}
      {:ok, effects, instances} = Instance.creature_event(instances, context.world, event)
      {instances, effects}
    end)
  end

  defp start(instances, context, field), do: Instance.command(instances, context.world, field, 1, :raw)

  defp die(instances, context, entry, guid),
    do: Instance.creature_event(instances, context.world, event(entry, guid, :death))

  defp event(entry, guid, event), do: %{creature_entry: entry, creature_guid: guid, db_guid: nil, event: event}

  defp opened(effects), do: for(%Effects.OperateGameObject{entry: entry, action: :open} <- effects, do: entry)

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 70, {:player, 100}, 100, "instance_uldaman")
    %{world: world, instances: instances}
  end
end
