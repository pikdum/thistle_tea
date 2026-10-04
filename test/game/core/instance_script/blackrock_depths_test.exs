defmodule ThistleTea.Game.Core.InstanceScript.BlackrockDepthsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @braziers [174_744, 174_745]
  @golem_doors [170_573, 170_574]
  @throne_room 170_575
  @tomb_enter 170_576
  @tomb_exit 170_577
  @magmus 9_938
  @doomrel 9_039
  @seven [9_035, 9_038, 9_040, 9_037, 9_036, 9_034, @doomrel]
  @grimstone 10_096
  @arena_stage 46
  @beast_gate 161_525
  @champion_gate 161_522
  @exit_gate 161_524
  @jail_gate 161_523

  setup [:dungeon]

  describe "InstanceScript.scripted_door?/2" do
    test "keeps players' hands off the doors the depths open themselves" do
      for door <- @golem_doors ++ [@throne_room, @tomb_enter, @tomb_exit] do
        assert InstanceScript.scripted_door?("instance_blackrock_depths", door)
      end

      refute InstanceScript.scripted_door?("instance_blackrock_depths", hd(@braziers))
      refute InstanceScript.scripted_door?("instance_deadmines", @throne_room)
      refute InstanceScript.scripted_door?(nil, @throne_room)
    end
  end

  describe "game_object_used/3" do
    test "both Shadowforge Braziers open the Golem Room", context do
      [north, south] = @braziers
      assert {:ok, [], instances} = Instance.game_object_used(context.instances, context.world, north)
      assert {:ok, [], ^instances} = Instance.game_object_used(instances, context.world, north)

      assert {:ok, effects, instances} = Instance.game_object_used(instances, context.world, south)
      assert opened(effects) == @golem_doors
      assert %Effects.MonsterTalk{creature_entry: @magmus, broadcast_text_id: 5_430} in effects

      assert {:ok, [], _} = Instance.game_object_used(instances, context.world, north)

      for door <- @golem_doors do
        assert {:ok, [%Effects.OperateGameObject{action: :open}], ^instances} =
                 Instance.game_object_spawned(instances, context.world, door)
      end
    end

    test "a Seven dwarf walking home does not undo the Lyceum", context do
      instances = lit(context)
      assert {:ok, 3, [], instances} = Instance.command(instances, context.world, 4, 2, :raw)
      assert {:ok, [_], _} = Instance.game_object_spawned(instances, context.world, hd(@golem_doors))
    end
  end

  describe "creature_event/3" do
    test "Magmus holds the Golem Room shut while he fights and opens the Throne Room on death", context do
      instances = lit(context)

      assert {:ok, effects, instances} = magmus(instances, context, :aggro)
      assert closed(effects) == @golem_doors

      assert {:ok, effects, instances} = magmus(instances, context, :evade)
      assert opened(effects) == @golem_doors

      {:ok, _effects, instances} = magmus(instances, context, :aggro)
      assert {:ok, effects, instances} = magmus(instances, context, :death)
      assert opened(effects) == @golem_doors ++ [@throne_room]

      assert {:ok, [%Effects.OperateGameObject{action: :open}], ^instances} =
               Instance.game_object_spawned(instances, context.world, @throne_room)
    end

    test "Magmus keeps the Throne Room shut until he dies", context do
      assert {:ok, [], _} = Instance.game_object_spawned(context.instances, context.world, @throne_room)
    end
  end

  describe "Tomb of the Seven" do
    test "a challenge seals the tomb and calls the Seven in turn", context do
      assert {:ok, 1, effects, instances} = Instance.command(context.instances, context.world, 3, 1, :raw)
      assert closed(effects) == [@tomb_enter]
      assert %Effects.Schedule{key: {:tomb_call, 0}, delay_ms: 0} in effects

      instances =
        @seven
        |> Enum.with_index()
        |> Enum.reduce(instances, fn {dwarf, round}, instances ->
          assert {:ok, [call | next], instances} = Instance.timer(instances, context.world, {:tomb_call, round})
          assert %Effects.RunCreatureScript{creature_entry: ^dwarf, steps: steps} = call

          assert [
                   %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x100, datalong3: 2},
                   %ScriptStep{command: :set_faction, datalong: 54},
                   %ScriptStep{command: :zone_combat_pulse}
                 ] = steps

          expected = if round < 6, do: [%Effects.Schedule{key: {:tomb_call, round + 1}, delay_ms: 30_000}], else: []
          assert next == expected
          instances
        end)

      assert {:ok, effects, instances} =
               Instance.creature_event(instances, context.world, %{creature_entry: @doomrel, event: :death})

      assert opened(effects) == [@tomb_exit, @tomb_enter]
      assert %Effects.RespawnGameObject{db_guid: 399_065, duration_ms: 3_600_000} in effects
      assert Instance.read(instances, context.world, 3) == {:ok, 3}

      assert {:ok, [%Effects.OperateGameObject{action: :open}], _} =
               Instance.game_object_spawned(instances, context.world, @tomb_exit)
    end

    test "a called dwarf giving up its fight stands the Seven down", context do
      {:ok, 1, _effects, instances} = Instance.command(context.instances, context.world, 3, 1, :raw)
      {:ok, _effects, instances} = Instance.timer(instances, context.world, {:tomb_call, 0})

      assert {:ok, effects, instances} =
               Instance.creature_event(instances, context.world, %{creature_entry: 9_035, event: :evade})

      assert opened(effects) == [@tomb_enter]
      assert Enum.count(effects, &match?(%Effects.RunCreatureScript{}, &1)) == 7
      assert %Effects.CancelSchedules{} = Enum.find(effects, &match?(%Effects.CancelSchedules{}, &1))
      assert Instance.read(instances, context.world, 3) == {:ok, 0}
      assert {:ok, [], _} = Instance.timer(instances, context.world, {:tomb_call, 1})

      assert {:ok, 1, _effects, _instances} = Instance.command(instances, context.world, 3, 1, :raw)
    end

    test "dwarves leaving combat outside the challenge change nothing", context do
      assert {:ok, [], _} =
               Instance.creature_event(context.instances, context.world, %{creature_entry: 9_035, event: :evade})
    end
  end

  describe "Ring of Law" do
    test "stepping into the ring shuts the jail gate and brings out Grimstone", context do
      assert {:ok, 1, effects, instances} = ring(context.instances, context.world, 1)
      assert closed(effects) == [@jail_gate]

      assert [%Effects.SummonCreature{entry: @grimstone, despawn_type: 7, steps: [_walk, sentence, start]}] =
               Enum.filter(effects, &match?(%Effects.SummonCreature{}, &1))

      assert %ScriptStep{command: :talk, dataint: 5_441, delay_ms: 1_000} = sentence
      assert %ScriptStep{command: :start_waypoints, datalong: 5, datalong2: 0} = start
      assert {:ok, 1, [], _instances} = ring(instances, context.world, 1)
    end

    test "Grimstone opens the beast gate and the champion gate in turn", context do
      assert {:ok, 1, effects, instances} = Instance.command(context.instances, context.world, @arena_stage, 1, :raw)
      assert opened(effects) == [@beast_gate]
      assert {:ok, 2, effects, _instances} = Instance.command(instances, context.world, @arena_stage, 2, :raw)
      assert closed(effects) == [@beast_gate]
      assert opened(effects) == [@champion_gate]
    end

    test "eight slain beasts send Grimstone on to the champion gate", context do
      {:ok, 1, _effects, instances} = ring(context.instances, context.world, 1)
      {:ok, 1, _effects, instances} = Instance.command(instances, context.world, @arena_stage, 1, :raw)
      instances = Enum.reduce(1..8, instances, &arena(&2, context.world, 8_925, &1, :spawned))

      instances =
        Enum.reduce(1..7, instances, fn guid, instances ->
          assert {:ok, [], instances} = Instance.creature_event(instances, context.world, event(8_926, guid, :death))
          instances
        end)

      assert {:ok, [%Effects.Schedule{key: {:ring, :champion}, delay_ms: 10_000}], instances} =
               Instance.creature_event(instances, context.world, event(8_925, 8, :death))

      assert {:ok, effects, _instances} = Instance.timer(instances, context.world, {:ring, :champion})
      assert closed(effects) == [@beast_gate]
      assert [%Effects.RunCreatureScript{creature_entry: @grimstone, steps: [resume]}] = scripts(effects)
      assert %ScriptStep{command: :start_waypoints, datalong2: 3} = resume
    end

    test "the champion's death leads to the exit opening and the crowd calming down", context do
      {:ok, 1, _effects, instances} = ring(context.instances, context.world, 1)
      instances = arena(instances, context.world, 9_031, 20, :spawned)

      assert {:ok, [%Effects.Schedule{key: {:ring, :finish}, delay_ms: 5_000}], instances} =
               Instance.creature_event(instances, context.world, event(9_031, 20, :death))

      assert {:ok, effects, instances} = Instance.timer(instances, context.world, {:ring, :finish})
      assert [%Effects.RunCreatureScript{steps: [%ScriptStep{datalong2: 5}]}] = scripts(effects)

      assert {:ok, 3, effects, instances} = ring(instances, context.world, 3)
      assert Enum.sort(opened(effects)) == Enum.sort([@exit_gate, @jail_gate])
      calm = scripts(effects)
      assert length(calm) == 7

      for script <- calm do
        assert %Effects.RunCreatureScript{within: {{595.78, -188.65, -35.5}, 69}, steps: [neutral]} = script
        assert %ScriptStep{command: :set_faction, datalong: 15} = neutral
      end

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: 8_916}], _instances} =
               Instance.creature_event(instances, context.world, event(8_916, 30, :spawned))
    end

    test "a wipe before the champion gives the ring back as it was", context do
      {:ok, 1, _effects, instances} = ring(context.instances, context.world, 1)
      {:ok, 1, _effects, instances} = Instance.command(instances, context.world, @arena_stage, 1, :raw)
      instances = Enum.reduce(1..3, instances, &arena(&2, context.world, 8_927, &1, :spawned))

      assert {:ok, effects, instances} = Instance.creature_event(instances, context.world, event(8_927, 2, :evade))
      assert closed(effects) == [@beast_gate]
      assert opened(effects) == [@jail_gate]
      assert Instance.read(instances, context.world, 0) == {:ok, 0}

      despawned = for %Effects.RunCreatureScript{steps: [%ScriptStep{command: :despawn}]} = s <- effects, do: s
      assert Enum.sort(Enum.map(despawned, &(&1.creature_guid || &1.creature_entry))) == [1, 2, 3, @grimstone]
      assert {:ok, [], _instances} = Instance.creature_event(instances, context.world, event(8_927, 3, :evade))
    end

    test "a wipe against the champion leaves it waiting until the challengers step back in", context do
      {:ok, 1, _effects, instances} = ring(context.instances, context.world, 1)
      instances = arena(instances, context.world, 9_028, 40, :spawned)

      assert {:ok, effects, instances} = Instance.creature_event(instances, context.world, event(9_028, 40, :evade))
      assert opened(effects) == [@jail_gate]
      assert Instance.read(instances, context.world, 0) == {:ok, 2}

      assert {:ok, 1, effects, _instances} = ring(instances, context.world, 1)
      assert closed(effects) == [@jail_gate]
      assert Enum.all?(scripts(effects), &match?(%{steps: [%ScriptStep{command: :zone_combat_pulse}]}, &1))
    end
  end

  defp ring(instances, world, value), do: Instance.command(instances, world, 0, value, :raw)

  defp arena(instances, world, entry, guid, type) do
    {:ok, _effects, instances} = Instance.creature_event(instances, world, event(entry, guid, type))
    instances
  end

  defp event(entry, guid, type), do: %{creature_entry: entry, creature_guid: guid, event: type}

  defp scripts(effects), do: Enum.filter(effects, &match?(%Effects.RunCreatureScript{}, &1))

  defp lit(context) do
    Enum.reduce(@braziers, context.instances, fn brazier, instances ->
      {:ok, _effects, instances} = Instance.game_object_used(instances, context.world, brazier)
      instances
    end)
  end

  defp magmus(instances, context, event),
    do: Instance.creature_event(instances, context.world, %{creature_entry: @magmus, event: event})

  defp opened(effects), do: for(%Effects.OperateGameObject{entry: entry, action: :open} <- effects, do: entry)
  defp closed(effects), do: for(%Effects.OperateGameObject{entry: entry, action: :close} <- effects, do: entry)

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 230, {:player, 100}, 100, "instance_blackrock_depths")
    %{world: world, instances: instances}
  end
end
