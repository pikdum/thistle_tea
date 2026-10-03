defmodule ThistleTea.Game.Core.AI.CreatureScript.ScourgeInvasionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @mouth 16_995

  describe "events/1" do
    test "the Mouth of Kel'Thuzad taunts its zone now and then" do
      %{actions: [[taunt]]} = Enum.find(CreatureScript.events(@mouth), &(&1.event_type == :timer_ooc))

      assert %ScriptStep{command: :talk, datalong: 6} = taunt
      assert ScriptStep.talk_text_ids(taunt) == [13_126, 13_124, 13_122, 13_123]
    end

    test "the Mouth proclaims an attack and concedes a defeated zone before departing" do
      events = CreatureScript.events(@mouth)

      %{actions: [[start]]} = Enum.find(events, &(&1.event_type == :script_event and &1.param1 == 7))
      assert ScriptStep.talk_text_ids(start) == [13_121, 13_125]

      %{actions: [[concede, depart]]} = Enum.find(events, &(&1.event_type == :script_event and &1.param1 == 8))
      assert ScriptStep.talk_text_ids(concede) == [13_165, 13_164, 13_163]
      assert %ScriptStep{command: :despawn} = depart
    end

    test "a camp's death bolt climbs the relay and proxy to the necropolis's health" do
      %{actions: [[relay_bolt]]} = hit(16_386, 28_351)
      assert %ScriptStep{datalong: 28_351, target_type: :nearest_creature_with_entry} = relay_bolt
      assert relay_bolt.target_param1 == 16_398

      %{actions: [[proxy_bolt]]} = hit(16_398, 28_351)
      assert %ScriptStep{target_param1: 16_421, target_param2: 200} = proxy_bolt

      assert Enum.any?(CreatureScript.events(16_386), &(&1.event_type == :spell_hit_target and &1.param1 == 28_351))
    end

    test "the third zap kills a necropolis's health, which brings the necropolis down" do
      zaps = Enum.filter(CreatureScript.events(16_421), &(&1.event_type == :hit_by_spell and &1.param1 == 28_386))
      assert [%{actions: [[%ScriptStep{command: :deal_damage, datalong: 100}]]}, increment] = zaps
      assert %{actions: [[%ScriptStep{command: :set_phase}]]} = increment

      %{actions: [[despawner, depart]]} = Enum.find(CreatureScript.events(16_421), &(&1.event_type == :death))
      assert %ScriptStep{datalong: 28_349, target_param1: 16_401} = despawner
      assert %ScriptStep{command: :despawn, datalong: 1_000} = depart
    end

    test "a damaged shard falls with Soul Revival and a death bolt to its relay" do
      %{actions: [[revival, bolt]]} = Enum.find(CreatureScript.events(16_172), &(&1.event_type == :death))

      assert %ScriptStep{datalong: 28_681, target_self?: true} = revival
      assert %ScriptStep{datalong: 28_351, target_param1: 16_386} = bolt
    end

    test "disrupting a cultist's ritual takes eight runes and raises a Shadow of Doom" do
      %{actions: [[runes, shadow, suicide]]} =
        Enum.find(CreatureScript.events(16_230), &(&1.event_type == :script_event and &1.param1 == 7166))

      assert %ScriptStep{command: :remove_item, datalong: 22_484, datalong2: 8} = runes
      assert %ScriptStep{command: :summon_creature, datalong: 16_143, sub_scripts: %{1 => [_ | _]}} = shadow
      assert %ScriptStep{datalong: 3617} = suicide
    end

    test "a Shadow of Doom's death strikes the damaged shard" do
      %{actions: [[strike]]} = Enum.find(CreatureScript.events(16_143), &(&1.event_type == :death))
      assert %ScriptStep{datalong: 28_056, target_self?: true} = strike
    end
  end

  defp hit(entry, spell_id),
    do: Enum.find(CreatureScript.events(entry), &(&1.event_type == :hit_by_spell and &1.param1 == spell_id))
end
