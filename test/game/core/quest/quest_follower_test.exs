defmodule ThistleTea.Game.Core.Quest.QuestFollowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest.QuestFollower
  alias ThistleTea.Game.Core.Quest.QuestFollower.Catalog

  setup [:follower]

  describe "start_steps/1" do
    test "follows the player once the accept actions run", %{follower: follower} do
      assert [_event, say, faction, flags, follow] = QuestFollower.start_steps(follower)

      assert %ScriptStep{command: :talk, dataint: 100, target_type: :provided} = say
      assert %ScriptStep{command: :set_faction, datalong: 113} = faction
      assert %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0xFFFF_FFFF, datalong3: 2} = flags
      assert %ScriptStep{command: :movement, datalong: 15, position: {3.0, +0.0, +0.0, angle}} = follow
      assert_in_delta angle, :math.pi() / 2, 0.0001
    end

    test "fails the quest and respawns the follower if it dies or is left behind", %{follower: follower} do
      assert [%ScriptStep{command: :start_map_event} = event | _rest] = QuestFollower.start_steps(follower)

      assert %ScriptStep{datalong: 4_242, abort_on_failure?: true} = event
      assert event.failure_condition == %Condition{type: :escort, value1: 1, value2: 100}

      assert [%ScriptStep{command: :fail_quest, datalong: 4_242}, %ScriptStep{command: :respawn_creature}] =
               Map.fetch!(event.sub_scripts, event.dataint4)
    end

    test "credits the group and plays the arrival once the goal is beside the follower", %{follower: follower} do
      [event | _rest] = QuestFollower.start_steps(follower)

      assert %Condition{type: :nearby_creature, value1: 6_015, value2: 5, swap_targets?: true} =
               event.success_condition

      assert [
               %ScriptStep{command: :movement, datalong: 0},
               %ScriptStep{command: :quest_explored, datalong: 4_242, datalong2: 100, datalong3: 1},
               %ScriptStep{command: :talk, dataint: 101, target_type: :provided},
               %ScriptStep{command: :talk, dataint: 102, target_type: :nearest_creature_with_entry, delay_ms: 2_000},
               %ScriptStep{command: :despawn, delay_ms: 6_000, datalong2: 0}
             ] = Map.fetch!(event.sub_scripts, event.dataint2)
    end

    test "can turn on the player at its goal instead of crediting them", %{follower: follower} do
      follower = %{follower | credit?: false, despawn_ms: nil, arrive: [{:faction, 14}, {:attack, :player}]}
      [event | _rest] = QuestFollower.start_steps(follower)

      assert [
               %ScriptStep{command: :movement, datalong: 0},
               %ScriptStep{command: :set_faction, datalong: 14},
               %ScriptStep{command: :attack_start, target_type: :provided}
             ] = Map.fetch!(event.sub_scripts, event.dataint2)
    end

    test "can head for a place instead of a creature", %{follower: follower} do
      follower = %{follower | goal: {:point, {1.0, 2.0, 3.0}, 10}}
      [event | _rest] = QuestFollower.start_steps(follower)

      assert event.success_condition == %Condition{
               type: :distance_to_position,
               value1: 1.0,
               value2: 2.0,
               value3: 3.0,
               value4: 10,
               swap_targets?: true
             }
    end
  end

  describe "gossip_condition/1" do
    test "offers the gossip start while the quest is incomplete in the log", %{follower: follower} do
      assert QuestFollower.gossip_condition(follower) == %Condition{type: :quest_taken, value1: 4_242, value2: 1}
    end
  end

  describe "summon_entries/1" do
    test "lists the creatures its actions summon", %{follower: follower} do
      follower = %{follower | arrive: [{:summon, 77, {1.0, 2.0, 3.0, 0.0}, []}]}
      assert QuestFollower.summon_entries(follower) == [77]
    end
  end

  describe "Catalog" do
    test "lowers every ported follower" do
      for %QuestFollower{} = follower <- Catalog.all() do
        assert [%ScriptStep{command: :start_map_event} | _rest] = QuestFollower.start_steps(follower)
      end
    end
  end

  defp follower(_context) do
    follower = %QuestFollower{
      quest_id: 4_242,
      entry: 6_016,
      goal: {6_015, 5},
      distance: 3.0,
      despawn_ms: 6_000,
      accept: [{:say, 100}, {:faction, 113}],
      arrive: [{:say, 101}, {:after, 2_000, {:say_by, 6_015, 102}}]
    }

    %{follower: follower}
  end
end
