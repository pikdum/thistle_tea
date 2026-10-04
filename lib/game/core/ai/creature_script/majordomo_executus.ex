defmodule ThistleTea.Game.Core.AI.CreatureScript.MajordomoExecutus do
  @moduledoc """
  vmangos `boss_majordomo_executus`: the steward of the Molten Core, his
  guard, and the summoning of Ragnaros.

  Majordomo arrives with four Flamewaker Elites and four Flamewaker Healers
  who fight and fall back as one group. He wraps himself in the Aegis of
  Ragnaros whenever he drops below half health, shields his guard with
  Magic Reflection or a Damage Shield every thirty seconds, and teleports
  his victim or another player into his fire pit, forgetting all threat as
  he does. He cannot be killed: the fight is against his guard. Each guard
  that falls spurs the rest with Encouragement, the healers turn immune once
  half the guard is down, and the last one standing becomes his Champion.
  When the guard is gone he submits, walks back to his post, and after his
  speech teleports to Ragnaros's lair, where his gossip starts the summoning.
  He calls Ragnaros out of the lava and his master burns him to ash.

  If the raid wipes, he sends any guard still standing away and calls a
  fresh one. Phases 0 to 7 count the fallen guard; the counting events run
  highest phase first, so each death moves the count one step. vmangos also
  binds the guard to him with Separation Anxiety, punishing a guard pulled
  too far from him, which this port leaves out.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @majordomo 12_018
  @healer 11_663
  @elite 11_664
  @ragnaros 11_502

  @say_runes_destroyed 7_566
  @say_aggro 7_612
  @say_slay 9_425
  @say_defeat_submit 7_561
  @say_defeat_secrets 7_567
  @say_defeat_summon 7_568
  @say_last_add 8_545
  @say_whelps 7_655
  @say_behold 7_657
  @say_infidels 7_661

  @aegis 20_620
  @magic_reflection 20_619
  @damage_shield 21_075
  @teleport_victim 20_534
  @teleport_random 20_618
  @encouragement 21_086
  @immunity 21_087
  @champion 21_090
  @teleport_visual 19_484
  @summon_ragnaros 19_774

  @lava_steam 178_107
  @lava_splash 178_108

  @guard [
    {@elite, {737.945, -1_156.48, -118.945, 4.46804}},
    {@elite, {752.520, -1_191.02, -118.218, 2.49582}},
    {@elite, {752.953, -1_163.94, -118.869, 3.70010}},
    {@elite, {738.814, -1_197.40, -118.018, 1.83260}},
    {@healer, {746.939, -1_194.87, -118.016, 2.21657}},
    {@healer, {747.132, -1_158.87, -118.897, 4.03171}},
    {@healer, {757.116, -1_170.12, -118.793, 3.40339}},
    {@healer, {755.910, -1_184.46, -118.449, 2.80998}}
  ]

  @lair {847.103, -816.153, -229.775, 4.344}
  @summoning_spots %{
    2 => {839.1729, -811.2748, -229.5895},
    3 => {830.4840, -814.4016, -228.9452},
    4 => {831.4840, -815.4016, -228.9452}
  }
  @ragnaros_rises {838.308, -831.466, -232.185, 2.19911}
  @lava_steam_spot {838.951, -830.383, -230.206, 0.837757}
  @lava_splash_spot {839.279, -831.058, -230.202, 4.90438}

  @guard_size 8
  @defeated 8
  @in_lair 9
  @summoning 10

  @friendly 1_080
  @majordomo_field 8
  @done 3
  @unit_flags 46
  @npc_flags 147
  @immune_to_player 0x100
  @gossip 0x1
  @add_flags 1
  @remove_flags 2
  @triggered 0x02
  @aggro_and_evade_together 0x06
  @no_attack -1
  @dead_despawn 7
  @timed_or_dead 1
  @two_hours_ms 7_200_000
  @two_hours_s 7_200
  @guard_radius 150
  @creatures 2
  @despawn_script 1
  @join_script 1
  @all_attackers 8
  @player 0x2
  @point_motion 9
  @point_movement 0x02

  @impl CreatureScript
  def entries, do: [@majordomo]

  @impl CreatureScript
  def events(@majordomo) do
    [
      event(1, :spawned, [talk(@say_runes_destroyed) | call_guard()]),
      hostile(2, :evade, [%ScriptStep{command: :set_phase, datalong: 0} | dismiss_guard() ++ call_guard()]),
      hostile(3, :aggro, [talk(@say_aggro), cast_self(@aegis, @triggered)]),
      hostile(4, :kill, [talk(@say_slay)]),
      hostile(5, :hp, [cast_self(@aegis)], param1: 50, param2: 0, param3: 1_000, param4: 1_000),
      hostile(
        6,
        :timer_in_combat,
        CreatureScript.pick([[cast_self(@magic_reflection)], [cast_self(@damage_shield)]]),
        timer(30_000, 30_000, 30_000, 30_000)
      ),
      hostile(
        7,
        :timer_in_combat,
        CreatureScript.pick([
          [%ScriptStep{command: :cast_spell, datalong: @teleport_victim, target_type: :victim}, forget_threat()],
          [
            %ScriptStep{
              command: :cast_spell,
              datalong: @teleport_random,
              target_type: :hostile_random_not_top,
              target_param1: @player
            },
            forget_threat()
          ]
        ]),
        timer(10_000, 30_000, 20_000, 30_000)
      ),
      event(8, :evade, defeat_speech(), inverse_phase_mask: CreatureScript.only_in_phases([@defeated])),
      event(9, :script_event, summon_ragnaros(), param1: 0, param2: 0, inverse_phase_mask: in_phase(@in_lair))
    ] ++ fallen_guard() ++ summoning_walk()
  end

  def events(_entry), do: []

  defp call_guard do
    for {entry, position} <- @guard do
      %ScriptStep{
        command: :summon_creature,
        datalong: entry,
        dataint2: @join_script,
        dataint3: @no_attack,
        dataint4: @dead_despawn,
        position: position,
        sub_scripts: %{@join_script => [join_majordomo()]}
      }
    end
  end

  defp join_majordomo do
    %ScriptStep{
      command: :join_creature_group,
      datalong: @aggro_and_evade_together,
      target_type: :nearest_creature_with_entry,
      target_param1: @majordomo,
      target_param2: @guard_radius,
      position: {0.0, 0.0, 0.0, 0.0}
    }
  end

  defp dismiss_guard do
    for entry <- [@elite, @healer] do
      %ScriptStep{
        command: :start_script_for_all,
        datalong: @despawn_script,
        datalong2: @creatures,
        datalong3: entry,
        datalong4: @guard_radius,
        sub_scripts: %{@despawn_script => [%ScriptStep{command: :despawn}]}
      }
    end
  end

  defp fallen_guard do
    for fallen <- @guard_size..1//-1, {entry, offset} <- [{@elite, 0}, {@healer, 1}] do
      event(20 + fallen * 2 + offset, :summoned_just_died, [phase(fallen) | guard_falls(@guard_size - fallen)],
        param1: entry,
        inverse_phase_mask: in_phase(fallen - 1)
      )
    end
  end

  defp guard_falls(0) do
    [
      phase(@defeated),
      %ScriptStep{command: :set_instance_data, datalong: @majordomo_field, datalong2: @done},
      %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: @immune_to_player, datalong3: @add_flags},
      %ScriptStep{command: :enter_evade}
    ]
  end

  defp guard_falls(1) do
    [talk(@say_last_add), cast_self(@encouragement, @triggered), cast_self(@immunity, @triggered)] ++
      for entry <- [@elite, @healer] do
        %ScriptStep{
          command: :cast_spell,
          datalong: @champion,
          datalong2: @triggered,
          target_type: :nearest_creature_with_entry,
          target_param1: entry,
          target_param2: @guard_radius
        }
      end
  end

  defp guard_falls(standing) when standing <= div(@guard_size, 2),
    do: [cast_self(@encouragement, @triggered), cast_self(@immunity, @triggered)]

  defp guard_falls(_standing), do: [cast_self(@encouragement, @triggered)]

  defp defeat_speech do
    [
      CreatureScript.timed([
        at(2_400, CreatureScript.faction(@friendly)),
        at(2_400, talk(@say_defeat_submit)),
        at(10_100, talk(@say_defeat_secrets)),
        at(18_700, talk(@say_defeat_summon)),
        at(36_300, cast_self(@teleport_visual)),
        at(37_800, %ScriptStep{command: :teleport_to, position: @lair}),
        at(37_900, %ScriptStep{command: :set_home_position, position: @lair}),
        at(37_900, phase(@in_lair)),
        at(37_900, %ScriptStep{command: :modify_flags, datalong: @npc_flags, datalong2: @gossip, datalong3: @add_flags})
      ])
    ]
  end

  defp summon_ragnaros do
    [
      phase(@summoning),
      %ScriptStep{command: :modify_flags, datalong: @npc_flags, datalong2: @gossip, datalong3: @remove_flags},
      CreatureScript.timed([
        at(6_000, walk_to(2)),
        at(6_000, %ScriptStep{
          command: :summon_object,
          datalong: @lava_steam,
          datalong2: @two_hours_s,
          position: @lava_steam_spot
        }),
        at(6_000, %ScriptStep{
          command: :summon_object,
          datalong: @lava_splash,
          datalong2: @two_hours_s,
          position: @lava_splash_spot
        }),
        at(6_000, cast_self(@summon_ragnaros)),
        at(6_000, talk(@say_whelps)),
        at(21_000, talk(@say_behold)),
        at(28_000, %ScriptStep{
          command: :summon_creature,
          datalong: @ragnaros,
          datalong2: @two_hours_ms,
          dataint3: @no_attack,
          dataint4: @timed_or_dead,
          position: @ragnaros_rises
        }),
        at(28_500, %ScriptStep{
          command: :turn_to,
          target_type: :nearest_creature_with_entry,
          target_param1: @ragnaros,
          target_param2: 100
        }),
        at(50_000, talk(@say_infidels)),
        at(75_000, %ScriptStep{command: :invincibility, datalong: 0})
      ])
    ]
  end

  defp summoning_walk do
    for {point, next} <- [{2, 3}, {3, 4}] do
      event(50 + point, :movement_inform, [walk_to(next)],
        param1: @point_motion,
        param2: point,
        inverse_phase_mask: in_phase(@summoning)
      )
    end
  end

  defp walk_to(point) do
    {x, y, z} = Map.fetch!(@summoning_spots, point)
    %ScriptStep{command: :move_to, datalong4: @point_movement, dataint: point, position: {x, y, z, 0.0}}
  end

  defp forget_threat,
    do: %ScriptStep{command: :modify_threat, datalong: @all_attackers, position: {-100.0, 0.0, 0.0, 0.0}}

  defp hostile(index, type, steps, opts \\ []),
    do: event(index, type, steps, [inverse_phase_mask: CreatureScript.only_in_phases(Enum.to_list(0..7))] ++ opts)

  defp event(index, type, steps, opts \\ []), do: CreatureScript.event(@majordomo, index, type, steps, opts)

  defp in_phase(phase), do: CreatureScript.only_in_phases([phase])
  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}

  defp timer(initial_min, initial_max, repeat_min, repeat_max),
    do: [param1: initial_min, param2: initial_max, param3: repeat_min, param4: repeat_max]

  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}
end
