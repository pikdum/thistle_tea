defmodule ThistleTea.Game.Core.AI.CreatureScript.ShakesOBreen do
  @moduledoc """
  vmangos `npc_shakes_o_breen`, the Faldir's Cove first mate behind Death From
  Below (667) in the Arathi Highlands.

  Accepting the quest sounds the alarm, and the Daggerspine naga come ashore
  for Shakes in three waves twenty seconds apart: two raiders and a
  sorceress, then two raiders, then two raiders and a sorceress as Shakes
  rallies the player. The first raider ashore yells a challenge. Once the
  third wave is beaten, the quest completes for the player who accepted it
  and their group. If Shakes dies, or the player strays more than 150 yards
  from him, the quest fails and he starts over.

  The accepting player is kept as the target of a scripted map event named
  after the quest. The naga charge Shakes directly instead of wading ashore
  to his side first, and they still give experience and loot.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @shakes 2_610
  @raider 2_595
  @sorceress 2_596
  @death_from_below 667

  @battle_stations 6_372
  @watery_grave 854
  @hold_them 863

  @idle 0
  @defending 1
  @last_wave 2

  @event_limit_s 600
  @max_distance 150
  @source_dead 1
  @failure_script 1
  @wave_interval_ms 20_000
  @naga_ms 60_000
  @timed_or_dead_despawn 1
  @attack_self 8
  @challenge_script 2
  @naga_reach 60
  @npc_flags_field 147
  @questgiver 0x2
  @add_flags 1
  @remove_flags 2

  @left {-2_154.049, -1_969.738, 15.371, 5.54}
  @right {-2_157.606, -1_972.530, 15.552, 5.54}
  @rear {-2_157.533, -1_968.904, 15.410, 5.54}

  @impl CreatureScript
  def entries, do: [@shakes]

  @impl CreatureScript
  def events(@shakes) do
    endings =
      for type <- [:summoned_just_died, :summoned_just_despawn], entry <- [@raider, @sorceress], do: {type, entry}

    endings
    |> Enum.with_index(1)
    |> Enum.map(fn {{type, entry}, index} ->
      CreatureScript.event(@shakes, index, type, victory(),
        param1: entry,
        inverse_phase_mask: CreatureScript.only_in_phases([@last_wave]),
        condition: naga_beaten()
      )
    end)
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @death_from_below => [
        %ScriptStep{command: :talk, dataint: @battle_stations},
        %ScriptStep{
          command: :start_map_event,
          datalong: @death_from_below,
          datalong2: @event_limit_s,
          dataint4: @failure_script,
          abort_on_failure?: true,
          failure_condition: %Condition{type: :escort, value1: @source_dead, value2: @max_distance},
          sub_scripts: %{
            @failure_script => [
              %ScriptStep{command: :fail_quest, datalong: @death_from_below},
              %ScriptStep{command: :respawn_creature, datalong: 1}
            ]
          }
        },
        %ScriptStep{command: :set_phase, datalong: @defending},
        npc_flags(@remove_flags),
        CreatureScript.timed(waves())
      ]
    }
  end

  defp waves do
    [
      {1, [summon(@raider, @left, challenge: true), summon(@raider, @right), summon(@sorceress, @rear)]},
      {2, [summon(@raider, @left), summon(@raider, @right)]},
      {3,
       [
         %ScriptStep{command: :talk, dataint: @hold_them},
         %ScriptStep{command: :set_phase, datalong: @last_wave},
         summon(@raider, @left),
         summon(@raider, @right),
         summon(@sorceress, @rear)
       ]}
    ]
    |> Enum.flat_map(fn {wave, steps} ->
      Enum.map(steps, &%{&1 | delay_ms: wave * @wave_interval_ms, condition: defending()})
    end)
  end

  defp victory do
    [
      %ScriptStep{
        command: :quest_explored,
        datalong: @death_from_below,
        datalong3: 1,
        target_type: :map_event_target,
        target_param1: @death_from_below
      },
      %ScriptStep{command: :end_map_event, datalong: @death_from_below, datalong2: 1},
      %ScriptStep{command: :set_phase, datalong: @idle},
      npc_flags(@add_flags)
    ]
  end

  defp summon(entry, position, opts \\ []) do
    challenge = if Keyword.get(opts, :challenge, false), do: [%ScriptStep{command: :talk, dataint: @watery_grave}]

    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @naga_ms,
      dataint2: if(challenge, do: @challenge_script, else: 0),
      dataint3: @attack_self,
      dataint4: @timed_or_dead_despawn,
      position: position,
      sub_scripts: if(challenge, do: %{@challenge_script => challenge}, else: %{})
    }
  end

  defp naga_beaten do
    %Condition{
      type: :and,
      children: Enum.map([@raider, @sorceress], &naga_ashore/1)
    }
  end

  defp naga_ashore(entry) do
    %Condition{type: :nearby_creature, value1: entry, value2: @naga_reach, swap_targets?: true, reverse?: true}
  end

  defp defending, do: %Condition{type: :map_event_active, value1: @death_from_below}

  defp npc_flags(mode),
    do: %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: @questgiver, datalong3: mode}
end
