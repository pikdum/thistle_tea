defmodule ThistleTea.Game.Core.AI.CreatureScript.TapokeSlimJahn do
  @moduledoc """
  vmangos `npc_tapoke_slim_jahn` and `npc_slims_friend`, the brawl that ends
  the eleventh part of The Missing Diplomat (1249) in Menethil Harbor.

  The escape itself is the escort in `Core.Quest.QuestEscort.Catalog`:
  accepting the quest from Mikhail sends Slim sneaking out of the inn, and he
  starts running at the mailbox, where he can be attacked; reaching the gate
  fails the quest. Once in a fight he calls a friend, boasting about it if he
  is fleeing the player, and nobody can beat him below a fifth of his health:
  there his friend backs out, Slim gives up, owns up to the job, and the
  quest completes for the player who started the chase and their group
  before he slips back to the inn. Mikhail greets him whenever he turns up
  there again.

  His friend opens with a poisoned blade, backstabs, and slows its target.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @slim 4_962
  @friend 4_971
  @mikhail 4_963
  @missing_diplomat 1_249

  @bet_you_thought 5_827
  @more_than_i_bargained_for 5_828
  @ill_talk 1_743
  @notes_from_the_job 1_744
  @commotion_died_down 4_169

  @call_friends 16_457
  @poison_proc 3_616
  @slowing_poison 7_992
  @backstab 15_582

  @friendly_to_all 35
  @yield_pct 20
  @beg 20
  @talk 1
  @aura_not_present 0x20
  @creatures 2
  @friend_reach 30
  @mikhail_reach 20
  @stand_down_script 1
  @despawn_script 2
  @despawn_delay_ms 1_000
  @respawn_s 2

  @impl CreatureScript
  def entries, do: [@slim, @friend]

  @impl CreatureScript
  def events(@slim) do
    [
      CreatureScript.event(@slim, 1, :hp, give_up(), param1: @yield_pct, param2: 0, condition: escaping()),
      CreatureScript.event(@slim, 2, :aggro, call_friend(), condition: %{friend_nearby() | reverse?: true}),
      CreatureScript.event(@slim, 3, :spawned, [greeting()]),
      CreatureScript.event(@slim, 4, :death, [friend(@despawn_script)])
    ]
  end

  def events(@friend) do
    [
      CreatureScript.event(@friend, 1, :spawned, [
        %ScriptStep{command: :cast_spell, datalong: @poison_proc, target_self?: true}
      ]),
      CreatureScript.event(@friend, 2, :timer_in_combat, [cast_on_victim(@slowing_poison, @aura_not_present)],
        param1: 5_000,
        param2: 8_900,
        param3: 8_400,
        param4: 15_300
      ),
      CreatureScript.event(@friend, 3, :timer_in_combat, [cast_on_victim(@backstab, 0)],
        param1: 500,
        param2: 500,
        param3: 2_100,
        param4: 5_600
      )
    ]
  end

  defp give_up do
    [
      friend(@stand_down_script),
      %ScriptStep{command: :set_faction, datalong: @friendly_to_all},
      %ScriptStep{command: :combat_stop},
      %ScriptStep{command: :movement, datalong: 0},
      %ScriptStep{command: :set_run, datalong: 0},
      CreatureScript.timed([
        %ScriptStep{command: :turn_to, target_type: :map_event_target, target_param1: @missing_diplomat},
        %{friend(@despawn_script) | delay_ms: 2_000},
        %ScriptStep{command: :emote, datalong: @beg, delay_ms: 2_000},
        %{talk(@ill_talk) | delay_ms: 2_000},
        %ScriptStep{command: :emote, datalong: @talk, delay_ms: 6_000},
        %{talk(@notes_from_the_job) | delay_ms: 6_000},
        %{credit() | delay_ms: 12_000},
        %ScriptStep{command: :end_map_event, datalong: @missing_diplomat, datalong2: 1, delay_ms: 12_000},
        %ScriptStep{command: :despawn, datalong: @despawn_delay_ms, datalong2: @respawn_s, delay_ms: 12_000}
      ])
    ]
  end

  defp call_friend do
    [
      %ScriptStep{command: :cast_spell, datalong: @call_friends, target_self?: true},
      %{talk(@bet_you_thought) | condition: escaping()}
    ]
  end

  defp greeting do
    %ScriptStep{
      command: :talk,
      dataint: @commotion_died_down,
      target_type: :nearest_creature_with_entry,
      target_param1: @mikhail,
      target_param2: @mikhail_reach,
      swap_final?: true
    }
  end

  defp friend(script_id) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: script_id,
      datalong2: @creatures,
      datalong3: @friend,
      datalong4: @friend_reach,
      sub_scripts: %{
        @stand_down_script => [
          %ScriptStep{command: :set_faction, datalong: @friendly_to_all},
          %ScriptStep{command: :combat_stop},
          talk(@more_than_i_bargained_for)
        ],
        @despawn_script => [%ScriptStep{command: :despawn}]
      }
    }
  end

  defp cast_on_victim(spell_id, flags),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_type: :victim}

  defp escaping, do: %Condition{type: :map_event_active, value1: @missing_diplomat}

  defp friend_nearby do
    %Condition{type: :nearby_creature, value1: @friend, value2: @friend_reach, swap_targets?: true}
  end

  defp credit do
    %ScriptStep{
      command: :quest_explored,
      datalong: @missing_diplomat,
      datalong3: 1,
      target_type: :map_event_target,
      target_param1: @missing_diplomat
    }
  end

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
end
