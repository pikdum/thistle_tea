defmodule ThistleTea.Game.Core.AI.CreatureScript.DashelStonefist do
  @moduledoc """
  vmangos `npc_dashel_stonefist`, the Old Town brawler behind the eighth part
  of The Missing Diplomat (1447) in Stormwind.

  Accepting the quest turns Dashel on the player with two Old Town Thugs, who
  give up after thirty seconds. Nobody can beat him below a fifth of his
  health: there he gives up, calls off whoever is still fighting, and walks
  back to his spot. If a thug is still standing, Dashel sends both home with a
  word, each answering him on the way out, before the quest completes for the
  player who started the brawl and their group. A fight that resets before he
  gives up, or ends with his death, fails the quest and sends the thugs away.

  The accepting player is kept as the target of a scripted map event named
  after the quest, so the credit still reaches them after Dashel has walked
  home. Each thug learns its part from the script that summons it.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @dashel 4_961
  @thug 4_969
  @missing_diplomat 1_447

  @gonna_get_it 1_961
  @enough_fighting 1_712
  @back_off 1_713
  @waste_of_practice 1_716
  @no_problem 1_715

  @brawler 189
  @friendly_to_all 35
  @template_faction 0
  @npc_flags_field 147
  @questgiver 0x2
  @add_flags 1
  @remove_flags 2
  @yield_pct 20
  @percent 1

  @idle 0
  @fighting 1
  @yielded 2
  @settling 3

  @first_thug 1
  @second_thug 2
  @leave 1
  @thug_stay_ms 30_000
  @timed_or_dead_despawn 1
  @provided 0
  @creatures 2
  @thug_reach 40
  @event_limit_s 600
  @stand_down_script 1
  @leave_script 2
  @despawn_script 3

  @thugs [
    {@first_thug, {-8_676.075, 443.744, 99.632, 3.982}, {-8_669.339, 448.363, 99.740}},
    {@second_thug, {-8_685.417, 443.131, 99.527, 5.760}, {-8_686.397, 447.596, 99.994}}
  ]

  @impl CreatureScript
  def entries, do: [@dashel, @thug]

  @impl CreatureScript
  def events(@dashel) do
    fighting = CreatureScript.only_in_phases([@fighting])
    yielded = CreatureScript.only_in_phases([@yielded])
    engaged = CreatureScript.only_in_phases([@fighting, @yielded])

    [
      CreatureScript.event(@dashel, 1, :hp, give_up(),
        param1: @yield_pct,
        param2: 0,
        param3: 1_000,
        param4: 1_000,
        inverse_phase_mask: fighting
      ),
      CreatureScript.event(@dashel, 2, :evade, [fail_quest(), thugs(@despawn_script) | reset()],
        inverse_phase_mask: fighting
      ),
      CreatureScript.event(@dashel, 3, :death, [fail_quest(), thugs(@despawn_script), end_event()],
        inverse_phase_mask: engaged
      ),
      CreatureScript.event(@dashel, 4, :reached_home, send_thugs_home(),
        inverse_phase_mask: yielded,
        condition: thugs_standing()
      ),
      CreatureScript.event(@dashel, 5, :reached_home, settle(3_000),
        inverse_phase_mask: yielded,
        condition: %{thugs_standing() | reverse?: true}
      )
    ]
  end

  def events(@thug) do
    Enum.map(@thugs, fn {part, _summon, walk_away} ->
      CreatureScript.event(@thug, part, :script_event, [leave(part, walk_away)],
        param1: @leave,
        inverse_phase_mask: CreatureScript.only_in_phases([part])
      )
    end)
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @missing_diplomat =>
        [
          %ScriptStep{command: :start_map_event, datalong: @missing_diplomat, datalong2: @event_limit_s},
          %ScriptStep{command: :set_phase, datalong: @fighting},
          talk(@gonna_get_it),
          %ScriptStep{command: :set_faction, datalong: @brawler},
          npc_flags(@remove_flags),
          %ScriptStep{command: :invincibility, datalong: @yield_pct, datalong2: @percent}
        ] ++ Enum.map(@thugs, &summon_thug/1) ++ [%ScriptStep{command: :attack_start}]
    }
  end

  defp give_up do
    [
      %ScriptStep{command: :set_phase, datalong: @yielded},
      talk(@enough_fighting),
      %ScriptStep{command: :set_faction, datalong: @friendly_to_all},
      thugs(@stand_down_script),
      %ScriptStep{command: :enter_evade}
    ]
  end

  defp send_thugs_home do
    [
      %ScriptStep{command: :set_phase, datalong: @settling},
      CreatureScript.timed([%{talk(@back_off) | delay_ms: 3_000}, %{thugs(@leave_script) | delay_ms: 3_000}]),
      settle_after(11_000)
    ]
  end

  defp settle(delay_ms), do: [%ScriptStep{command: :set_phase, datalong: @settling}, settle_after(delay_ms)]

  defp settle_after(delay_ms), do: CreatureScript.timed(Enum.map([credit() | reset()], &%{&1 | delay_ms: delay_ms}))

  defp reset do
    [
      %ScriptStep{command: :set_faction, datalong: @template_faction},
      npc_flags(@add_flags),
      %ScriptStep{command: :invincibility, datalong: 0},
      %ScriptStep{command: :set_phase, datalong: @idle},
      end_event()
    ]
  end

  defp summon_thug({part, position, _walk_away}) do
    %ScriptStep{
      command: :summon_creature,
      datalong: @thug,
      datalong2: @thug_stay_ms,
      dataint2: part,
      dataint3: @provided,
      dataint4: @timed_or_dead_despawn,
      position: position,
      sub_scripts: %{part => [%ScriptStep{command: :set_phase, datalong: part}]}
    }
  end

  defp leave(part, {x, y, z}) do
    {line, delay_ms} = if part == @first_thug, do: {@waste_of_practice, 3_000}, else: {@no_problem, 4_500}

    CreatureScript.timed([
      %{talk(line) | delay_ms: delay_ms},
      %ScriptStep{command: :move_to, position: {x, y, z, 0.0}, delay_ms: delay_ms + 2_500},
      %ScriptStep{command: :despawn, delay_ms: delay_ms + 5_500}
    ])
  end

  defp thugs(script_id) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: script_id,
      datalong2: @creatures,
      datalong3: @thug,
      datalong4: @thug_reach,
      sub_scripts: %{
        @stand_down_script => [
          %ScriptStep{command: :set_faction, datalong: @friendly_to_all},
          %ScriptStep{command: :enter_evade}
        ],
        @leave_script => [%ScriptStep{command: :send_script_event, datalong: @leave, target_self?: true}],
        @despawn_script => [%ScriptStep{command: :despawn}]
      }
    }
  end

  defp thugs_standing do
    %Condition{type: :nearby_creature, value1: @thug, value2: @thug_reach, swap_targets?: true}
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

  defp fail_quest do
    %ScriptStep{
      command: :fail_quest,
      datalong: @missing_diplomat,
      target_type: :map_event_target,
      target_param1: @missing_diplomat
    }
  end

  defp end_event, do: %ScriptStep{command: :end_map_event, datalong: @missing_diplomat}

  defp npc_flags(mode),
    do: %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: @questgiver, datalong3: mode}

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
end
