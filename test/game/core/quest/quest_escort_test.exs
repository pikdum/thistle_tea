defmodule ThistleTea.Game.Core.Quest.QuestEscortTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest.QuestEscort
  alias ThistleTea.Game.Core.Quest.QuestEscort.Catalog

  setup [:escort]

  describe "start_steps/1" do
    test "starts a map event that fails the quest and respawns the escortee", %{escort: escort} do
      assert [%ScriptStep{command: :start_map_event} = event | _rest] = QuestEscort.start_steps(escort)

      assert %ScriptStep{datalong: 4_242, abort_on_failure?: true} = event
      assert event.failure_condition == %Condition{type: :escort, value1: 1, value2: 80}
      assert event.success_condition == nil
      assert event.dataint2 == 0

      assert [%ScriptStep{command: :fail_quest, datalong: 4_242}, %ScriptStep{command: :respawn_creature} = respawn] =
               Map.fetch!(event.sub_scripts, event.dataint4)

      assert respawn.datalong == 1
    end

    test "runs the accept actions, clears the npc flags, and starts the path", %{escort: escort} do
      assert [_event, say, faction, run, flags, waypoints] = QuestEscort.start_steps(escort)

      assert %ScriptStep{command: :talk, dataint: 100, target_type: :provided} = say
      assert %ScriptStep{command: :set_faction, datalong: 232, datalong2: 1} = faction
      assert %ScriptStep{command: :set_run, datalong: 1, delay_ms: 3_000} = run
      assert %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0xFFFF_FFFF, datalong3: 2} = flags
      assert %ScriptStep{command: :start_waypoints, datalong: 4, datalong3: 2_500, dataint3: 4_242} = waypoints
    end

    test "lifts unit flags until the escortee respawns", %{escort: escort} do
      escort = %{escort | accept: [{:remove_unit_flags, 0x200}]}

      assert [_event, flags, _npc_flags, _waypoints] = QuestEscort.start_steps(escort)
      assert %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x200, datalong3: 2} = flags
    end

    test "starts the escort on the escortee near another quest giver", %{escort: escort} do
      escort = %{escort | giver: 5_151, accept: [{:invincible, 20}]}

      assert [%ScriptStep{command: :start_script_for_all, datalong: script_id} = forward] =
               QuestEscort.start_steps(escort)

      assert %ScriptStep{datalong2: 2, datalong3: 4_343, datalong4: 20} = forward

      assert [%ScriptStep{command: :start_map_event}, invincible, _flags, _waypoints] =
               Map.fetch!(forward.sub_scripts, script_id)

      assert %ScriptStep{command: :invincibility, datalong: 20, datalong2: 1} = invincible
    end
  end

  describe "point_steps/3" do
    test "fails the quest at a point and credits nobody without a credit point", %{escort: escort} do
      escort = %{escort | credit_point: nil, points: %{3 => [:fail]}}

      assert [%ScriptStep{command: :fail_quest, datalong: 4_242, target_type: :map_event_target}] =
               escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(3)

      refute escort
             |> QuestEscort.point_steps(9, 0)
             |> Map.values()
             |> List.flatten()
             |> Enum.any?(&(&1.command == :quest_explored))
    end

    test "speaks to the escorted player and credits them at the credit point", %{escort: escort} do
      points = QuestEscort.point_steps(escort, 9, 0)

      assert [say, credit] = Map.fetch!(points, 3)
      assert %ScriptStep{command: :talk, dataint: 101, target_type: :map_event_target, target_param1: 4_242} = say

      assert %ScriptStep{
               command: :quest_explored,
               datalong: 4_242,
               datalong2: 80,
               datalong3: 1,
               target_type: :map_event_target,
               target_param1: 4_242
             } = credit
    end

    test "ends the event and despawns once the last point's wait runs out", %{escort: escort} do
      assert [
               %ScriptStep{command: :end_map_event, datalong: 4_242, datalong2: 1, delay_ms: 7_000},
               %ScriptStep{command: :despawn, delay_ms: 7_000, datalong2: 0}
             ] = escort |> QuestEscort.point_steps(9, 7_000) |> Map.fetch!(9)

      assert [_end_event, %ScriptStep{command: :despawn, datalong2: 1}] =
               %{escort | instant_respawn?: true} |> QuestEscort.point_steps(9, 0) |> Map.fetch!(9)
    end

    test "summons ambushes at the escortee, the player, or nobody", %{escort: escort} do
      assert [at_escort, at_player, idle, speaker] = escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(5)

      assert %ScriptStep{command: :summon_creature, datalong: 77, dataint3: 8, dataint4: 1, datalong2: 25_000} =
               at_escort

      assert [%ScriptStep{command: :talk, dataint: 102, target_type: :provided}] =
               Map.fetch!(at_escort.sub_scripts, at_escort.dataint2)

      assert %ScriptStep{dataint3: 23, target_param1: 4_242, dataint4: 4, datalong2: 30_000, sub_scripts: %{}} =
               at_player

      assert %ScriptStep{dataint3: -1, dataint2: 0, position: {1.0, 2.0, 3.0, 0.5}} = idle

      assert %ScriptStep{
               command: :talk,
               dataint: 103,
               target_type: :nearest_creature_with_entry,
               target_param1: 88,
               swap_final?: true
             } = speaker
    end
  end

  describe "point actions" do
    test "hold the path until the escortee's summons are gone, then run the release", %{escort: escort} do
      escort = %{escort | points: %{4 => [{:hold, [{:say, 104}]}]}}

      assert [%ScriptStep{command: :hold_waypoints, datalong: 400_000, sub_scripts: %{1 => [release]}}] =
               escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(4)

      assert %ScriptStep{command: :talk, dataint: 104, target_type: :map_event_target, target_param1: 4_242} = release
    end

    test "end the event before the escortee dies, and emote through another creature", %{escort: escort} do
      escort = %{escort | points: %{4 => [{:emote_by, 9538, 37}, :die]}}

      assert [emote, end_event, die] = escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(4)

      assert %ScriptStep{
               command: :emote,
               datalong: 37,
               target_type: :nearest_creature_with_entry,
               target_param1: 9538,
               swap_final?: true
             } = emote

      assert %ScriptStep{command: :end_map_event, datalong: 4_242, datalong2: 1} = end_event
      assert %ScriptStep{command: :deal_damage, datalong: 100, datalong2: 1, target_self?: true} = die
    end

    test "pause the path and restore the escortee as a quest ender", %{escort: escort} do
      escort = %{escort | points: %{4 => [{:pause, 600_000}, {:npc_flags, 0x2}]}}

      assert [pause, flags] = escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(4)
      assert %ScriptStep{command: :hold_waypoints, datalong: 600_000, datalong2: 1, sub_scripts: subs} = pause
      assert subs == %{}
      assert %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 1} = flags
    end

    test "cast a triggered spell on the escortee", %{escort: escort} do
      escort = %{escort | points: %{4 => [{:after, 11_000, {:cast, 25_004}}]}}

      assert [
               %ScriptStep{
                 command: :cast_spell,
                 datalong: 25_004,
                 datalong2: 0x02,
                 target_self?: true,
                 delay_ms: 11_000
               }
             ] =
               escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(4)
    end

    test "cast a spell with its cast time, flag the escortee, and turn to and signal another creature",
         %{escort: escort} do
      escort = %{
        escort
        | points: %{
            4 => [{:cast, 25_813, triggered?: false}, {:unit_flags, 0x1000}, {:face, 15_491}, {:signal, 15_491, 2}]
          }
      }

      assert [cast, flags, face, signal] = escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(4)
      assert %ScriptStep{command: :cast_spell, datalong: 25_813, datalong2: 0, target_self?: true} = cast
      assert %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x1000, datalong3: 1} = flags

      assert %ScriptStep{command: :turn_to, target_type: :nearest_creature_with_entry, target_param1: 15_491} = face
      refute face.swap_final?

      assert %ScriptStep{
               command: :send_script_event,
               datalong: 2,
               target_type: :nearest_creature_with_entry,
               target_param1: 15_491,
               swap_final?: true
             } = signal
    end

    test "summon several at once, scattered around a point or the player", %{escort: escort} do
      escort = %{
        escort
        | points: %{
            4 => [
              {:summon, 77, {1.0, 2.0, 3.0, 0.5}, count: 3, scatter: 10.0},
              {:summon, 77, :player, attack: :escort, count: 4, scatter: 20.0}
            ]
          }
      }

      assert [around_point, around_player] = escort |> QuestEscort.point_steps(9, 0) |> Map.fetch!(4)
      assert %ScriptStep{count: 3, scatter: 10.0, at_target?: false, position: {1.0, 2.0, 3.0, 0.5}} = around_point

      assert %ScriptStep{
               count: 4,
               scatter: 20.0,
               at_target?: true,
               dataint3: 8,
               target_type: :map_event_target,
               target_param1: 4_242
             } = around_player
    end

    test "credit at the end of a scene", %{escort: escort} do
      assert [_say, %ScriptStep{command: :quest_explored, delay_ms: 23_000}] =
               %{escort | credit_delay_ms: 23_000} |> QuestEscort.point_steps(9, 0) |> Map.fetch!(3)
    end
  end

  describe "summon_entries/1" do
    test "lists each summoned entry once", %{escort: escort} do
      assert QuestEscort.summon_entries(escort) == [77, 78]
    end
  end

  describe "Catalog" do
    test "ports open-world escorts keyed by quest" do
      assert %QuestEscort{entry: 1379, credit_point: 23} = Catalog.get(309)
      assert %QuestEscort{entry: 4508, credit_point: 45} = Catalog.get(1144)
      assert %QuestEscort{entry: 11_832, credit_point: 9, path: [_ | _]} = Catalog.get(8447)
      assert 15_362 in Catalog.summon_entries()
      assert %QuestEscort{entry: 11_832, credit_point: nil, max_distance: 0, path: nil} = Catalog.get(8736)
      assert 15_491 in Catalog.summon_entries()
      assert 15_629 in Catalog.summon_entries()
      assert Catalog.get(1) == nil
      assert 2149 in Catalog.summon_entries()

      for %QuestEscort{} = escort <- Catalog.all() do
        assert is_list(QuestEscort.start_steps(escort))

        assert is_nil(escort.credit_point) or
                 Map.has_key?(QuestEscort.point_steps(escort, 1_000, 0), escort.credit_point)
      end
    end

    test "The Nightmare Manifests summons Eranikus, holds off ten phantasm waves, then brings him down" do
      points = 8736 |> Catalog.get() |> QuestEscort.point_steps(32, 0)

      assert %ScriptStep{command: :summon_creature, datalong: 15_491, delay_ms: 10_000, dataint4: 1} =
               Enum.find(points[16], &(&1.command == :summon_creature))

      assert Enum.any?(points[24], &match?(%ScriptStep{command: :send_script_event, datalong: 1}, &1))

      waves = Enum.filter(points[30], &(&1.command == :summon_creature))
      assert length(waves) == 12
      assert Enum.count(waves, & &1.at_target?) == 4
      assert waves |> Enum.map(& &1.count) |> Enum.sum() == 34

      descend = Enum.find(points[30], &(&1.command == :send_script_event))
      assert %ScriptStep{datalong: 2, delay_ms: 207_000} = descend
      assert Enum.all?(waves, &(&1.delay_ms <= descend.delay_ms))
    end
  end

  defp escort(_context) do
    escort = %QuestEscort{
      quest_id: 4_242,
      entry: 4_343,
      credit_point: 3,
      max_distance: 80,
      accept: [{:say, 100}, {:faction, 232}, {:after, 3_000, :run}],
      points: %{
        3 => [{:say, 101}],
        5 => [
          {:summon, 77, {1.0, 2.0, 3.0, 0.5}, attack: :escort, script: [{:say, 102}]},
          {:summon, 78, {1.0, 2.0, 3.0, 0.5}, attack: :player, despawn: {:timed_out_of_combat, 30_000}},
          {:summon, 77, {1.0, 2.0, 3.0, 0.5}, []},
          {:say_by, 88, 103}
        ]
      }
    }

    %{escort: escort}
  end
end
