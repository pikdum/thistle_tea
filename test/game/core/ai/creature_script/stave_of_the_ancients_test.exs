defmodule ThistleTea.Game.Core.AI.CreatureScript.StaveOfTheAncientsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context, as: ConditionContext
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @artorius 14_531
  @franklin 14_529
  @nelson 14_536
  @simone 14_527
  @precious 14_528
  @cleaner 14_503
  @demons %{@artorius => 14_535, @franklin => 14_534, @nelson => 14_530, @simone => 14_533}
  @quest 7_636

  describe "CreatureScript registry" do
    test "ports the four amiable demons, Precious, and The Cleaner" do
      assert Enum.all?([@artorius, @franklin, @nelson, @simone, @precious, @cleaner], &CreatureScript.ported?/1)
      assert Enum.all?([@precious, @cleaner], &(&1 in CreatureScript.summon_entries()))
      assert Enum.all?(Map.values(@demons) ++ [14_538], &(&1 in CreatureScript.creature_entries()))
    end
  end

  describe "gossip/0" do
    test "Franklin and Simone let a hunter on the quest call them out" do
      gossip = CreatureScript.gossip()

      for entry <- [@franklin, @simone] do
        assert %Gossip{texts: [], options: [%Gossip.Option{text: "Show me your real face, demon."} = option]} =
                 gossip[entry]

        assert %Condition{type: :quest_taken, value1: @quest, value2: 1} = option.condition
        assert [%ScriptStep{command: :send_script_event} | _] = option.steps
      end

      assert [_event, %ScriptStep{command: :emote, datalong: 11}] = hd(gossip[@simone].options).steps
      refute Map.has_key?(gossip, @artorius) or Map.has_key?(gossip, @nelson)
    end
  end

  describe "events/1" do
    test "a called-out demon halts, gestures, and takes its true form where it stands, walking again once respawned" do
      for {entry, demon} <- @demons do
        unmask = event(entry, :script_event)
        assert unmask.inverse_phase_mask == CreatureScript.only_in_phases([0])

        assert [
                 %ScriptStep{command: :movement, datalong: 0},
                 %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x1, datalong3: 2},
                 %ScriptStep{command: :set_phase, datalong: 1},
                 %ScriptStep{command: :start_script, sub_scripts: %{1 => timeline}}
               ] = hd(unmask.actions)

        assert [%ScriptStep{command: :emote, delay_ms: 5_000} | rest] = timeline

        assert [
                 %ScriptStep{command: :update_entry, datalong: ^demon, delay_ms: 10_000},
                 %ScriptStep{command: :set_home_position, datalong: 1},
                 %ScriptStep{command: :set_default_movement, datalong: 0},
                 %ScriptStep{command: :set_phase, datalong: 2} | _
               ] = rest

        assert %ScriptStep{command: :set_phase, datalong: 3, delay_ms: 1_210_000} = List.last(rest)

        assert [
                 %ScriptStep{command: :set_home_position, datalong: 2},
                 %ScriptStep{command: :set_default_movement, datalong: 2} | _
               ] = hd(event(entry, :spawned).actions)
      end
    end

    test "Simone brings Precious and turns her into the Devourer as she unmasks" do
      [_home, _route, summon] = hd(event(@simone, :spawned).actions)

      assert %ScriptStep{command: :summon_creature, datalong: @precious, dataint3: -1, dataint4: 7} = summon
      assert %Condition{type: :nearby_creature, value1: @precious, reverse?: true} = summon.condition

      [%ScriptStep{sub_scripts: %{1 => timeline}} | _] = event(@simone, :script_event).actions |> hd() |> Enum.reverse()

      assert %ScriptStep{
               command: :start_script,
               target_type: :nearest_creature_with_entry,
               target_param1: @precious,
               swap_final?: true,
               sub_scripts: %{1 => [%ScriptStep{command: :update_entry, datalong: 14_538}, %ScriptStep{datalong: 2}]}
             } = Enum.find(timeline, &(&1.command == :start_script))

      assert [%ScriptStep{command: :movement, datalong: 15, target_param1: @simone}] =
               hd(event(@precious, :spawned).actions)
    end

    test "only the hunter may pull a demon" do
      guard = Enum.find(CreatureScript.events(@franklin), &(&1.event_type == :aggro))

      assert guard.inverse_phase_mask == CreatureScript.only_in_phases([2, 3])
      assert guarded?(guard.condition, %Subject{kind: :player, race: 1, class: 1})
      assert guarded?(guard.condition, %Subject{kind: :pet, class: 1})
      refute guarded?(guard.condition, %Subject{kind: :player, race: 4, class: 3})
    end

    test "a second foe on the threat list calls The Cleaner and banishes the demon for fifteen minutes" do
      for entry <- Map.keys(@demons) do
        crowd = event(entry, :timer_in_combat)
        assert {crowd.param1, crowd.param3} == {1_000, 1_000}

        assert [%ScriptStep{command: :start_script, target_type: :hostile_second_aggro, sub_scripts: %{1 => banish}}] =
                 hd(crowd.actions)

        assert [%ScriptStep{command: :summon_creature, datalong: @cleaner} | _] = banish
        assert %ScriptStep{command: :despawn, datalong2: 900} = List.last(banish)
      end
    end

    test "a banished Simone takes the Devourer with her and Solenor his Creeping Doom" do
      assert banished(@simone) |> Enum.any?(&match?(%ScriptStep{command: :despawn, target_param1: 14_538}, &1))
      assert banished(@nelson) |> Enum.any?(&match?(%ScriptStep{command: :remove_guardians}, &1))

      assert [%ScriptStep{command: :summon_creature}, devourer_banishes_simone, %ScriptStep{command: :despawn}] =
               banished(@precious)

      assert %ScriptStep{command: :despawn, datalong2: 900, target_param1: 14_533, swap_final?: true} =
               devourer_banishes_simone
    end

    test "the banishment sets The Cleaner on the hunter and the meddler both" do
      hunter = Guid.from_low_guid(:player, Unique.integer())
      meddler = Guid.from_low_guid(:player, Unique.integer())
      demon = mob(@franklin)
      demon = %{demon | unit: %{demon.unit | target: hunter}}

      {demon, _blackboard} = Script.run(demon, Blackboard.new(), banished(@franklin), meddler, Context.new(0))

      assert [%Effects.SummonCreature{summon: summon, steps: steps, target_guid: ^meddler}] =
               Enum.filter(demon.internal.events, &match?(%Effects.SummonCreature{}, &1))

      assert %{entry: @cleaner, attack_guid: ^hunter, despawn_type: 1, despawn_delay_ms: 1_200_000} = summon
      assert [%ScriptStep{command: :attack_start, target_type: :provided}] = steps
      assert Enum.any?(demon.internal.events, &match?(%Effects.DespawnSelf{respawn_delay_ms: 900_000}, &1))
    end

    test "a demon left alone runs out of patience and slips away" do
      evade = event(@artorius, :evade)

      assert [%ScriptStep{command: :start_script, sub_scripts: %{1 => [%ScriptStep{delay_ms: 1_200_000} = restless]}}] =
               hd(evade.actions)

      assert %ScriptStep{command: :set_phase, datalong: 3} = restless

      slip = Enum.find(CreatureScript.events(@artorius), &(&1.inverse_phase_mask == CreatureScript.only_in_phases([3])))
      assert slip.event_type == :timer_ooc
      assert [%ScriptStep{command: :despawn, datalong2: 900}] = hd(slip.actions)
    end

    test "each demon answers the sting that undoes it" do
      assert stung(@artorius, 13_555) == [{:cast_spell, 23_299}, {:talk, 9_786}]
      assert stung(@artorius, 25_295) == [{:cast_spell, 23_299}, {:talk, 9_786}]
      assert stung(@franklin, 14_277) == [{:remove_aura, 23_257}, {:cast_spell, 23_260}]
      assert stung(@nelson, 14_268) == [{:cast_spell, 23_279}, {:talk, 9_785}]
      assert stung(@simone, 14_280) == [{:cast_spell, 23_207}, {:talk, 9_762}]

      frost_trap = Enum.find(CreatureScript.events(@nelson), &(&1.event_type == :aura))
      assert {frost_trap.param1, hd(hd(frost_trap.actions)).datalong} == {13_810, 23_272}
    end

    test "The Cleaner cannot be harmed and leaves once nobody is left to punish" do
      [spawned, aggro, evade, idle] = CreatureScript.events(@cleaner)

      assert [%ScriptStep{command: :cast_spell, datalong: 29_230, target_self?: true}] = hd(spawned.actions)
      assert [%ScriptStep{command: :talk, dataint: 9_726}] = hd(aggro.actions)
      assert [%ScriptStep{command: :despawn}] = hd(evade.actions)
      assert {idle.event_type, idle.param1} == {:timer_ooc, 3_000}
    end
  end

  defp event(entry, type), do: Enum.find(CreatureScript.events(entry), &(&1.event_type == type))

  defp banished(entry) do
    [%ScriptStep{sub_scripts: %{1 => steps}}] = hd(event(entry, :timer_in_combat).actions)
    steps
  end

  defp stung(entry, spell_id) do
    entry
    |> CreatureScript.events()
    |> Enum.find(&(&1.event_type == :hit_by_spell and &1.param1 == spell_id))
    |> Map.fetch!(:actions)
    |> hd()
    |> Enum.map(fn
      %ScriptStep{command: :talk, dataint: text} -> {:talk, text}
      %ScriptStep{command: command, datalong: spell} -> {command, spell}
    end)
  end

  defp guarded?(condition, subject), do: Condition.evaluate(ConditionContext.new(target: subject), condition) == :met

  defp mob(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 30_000, max_health: 30_000, level: 60, auras: [], flags: 0, stand_state: 0},
      movement_block: %MovementBlock{position: {-8_379.35, -987.762, 187.36, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "Klinfran the Crazed",
        creature: %Creature{ai_events: CreatureScript.events(entry)}
      }
    }
  end
end
