defmodule ThistleTea.Game.Core.AI.CreatureScript.Ragnaros do
  @moduledoc """
  vmangos `boss_ragnaros`: the Firelord in the heart of the Molten Core.

  Summoned by Majordomo Executus, Ragnaros rebukes him for waking him too
  soon, burns him to ash with Elemental Fire, and turns on the raid. The
  instance script holds his last roar and lowers his immunity once
  Majordomo is dead, since a creature's own pending scripts end whenever it
  enters or leaves combat.

  Ragnaros never moves. He fights wreathed in Elemental Fire and Melt
  Weapon, knocks back everyone near him with Wrath of Ragnaros and forgets
  all threat as he does, and calls a Flame of Ragnaros onto a mana user with
  Might of Ragnaros. Whenever his victim stands beyond the reach of his
  hammer, he hurls Magma Blasts at random players. Every three minutes he
  submerges for ninety seconds and eight Sons of Flame rise to defend him;
  he emerges early once they are all dead. A wipe ends the submerge cycle,
  so a fresh pull starts three minutes from the top.

  vmangos also erupts lava bursts around his chamber in waves of three and
  hands his threat list to the Sons of Flame, which this port leaves out:
  the Sons attack a random player instead.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @ragnaros 11_502
  @majordomo 12_018
  @son_of_flame 12_143

  @say_too_soon 7_636
  @say_fool 7_662
  @say_kill 7_626
  @say_hand 9_426
  @say_wrath 9_427
  @say_servants 8_572
  @say_minions 8_573

  @elemental_fire_kill 19_773
  @elemental_fire 20_563
  @melt_weapon 21_387
  @wrath_of_ragnaros 20_566
  @might_of_ragnaros 21_154
  @magma_blast 20_565
  @submerge_visual 20_567
  @submerge 21_859
  @emerge 20_568

  @sons [
    {811.448, -814.058, -233.177, 0.0},
    {819.699, -894.288, -231.258, 1.28281},
    {825.412, -869.328, -231.759, 1.24253},
    {842.542, -797.822, -233.340, 0.0},
    {866.345, -891.080, -231.449, 2.01042},
    {870.668, -821.862, -232.938, 0.0},
    {871.282, -858.217, -231.855, 2.46003},
    {887.501, -791.383, -231.108, 3.54988}
  ]

  @fighting 0
  @submerged 1
  @emerged 2

  @submerge_event 1
  @emerge_event 2
  @submerge_after_ms 180_000
  @emerge_after_ms 90_000

  @roar 15
  @stand 0
  @custom_stand 9
  @triggered 0x02
  @player 0x2
  @mana 0x4
  @hostile_random 4
  @timed_out_of_combat 4
  @son_lingers_ms 10_000
  @all_attackers 8
  @hammer_reach 23
  @players_only 1
  @at_least 1
  @chamber 150
  @creatures 2
  @despawn_script 1

  @impl CreatureScript
  def entries, do: [@ragnaros]

  @impl CreatureScript
  def events(@ragnaros) do
    [
      event(1, :spawned, [%ScriptStep{command: :set_combat_movement, datalong: 0}, arrival()]),
      event(2, :aggro, [
        cast_self(@melt_weapon, @triggered),
        cast_self(@elemental_fire, @triggered),
        later(@submerge_after_ms, @submerge_event)
      ]),
      event(3, :evade, [%ScriptStep{command: :stop_scripts}, phase(@fighting) | surface() ++ [dismiss_sons()]]),
      event(4, :kill, [talk(@say_kill)], param3: @players_only),
      fighting(
        5,
        [cast_self(@wrath_of_ragnaros), forget_threat(), talk(@say_wrath)],
        timer(25_000, 30_000, 25_000, 30_000)
      ),
      fighting(
        6,
        [
          %ScriptStep{
            command: :cast_spell,
            datalong: @might_of_ragnaros,
            target_type: :hostile_random,
            target_param1: @player + @mana
          }
          | CreatureScript.pick([[talk(@say_hand)], []])
        ],
        timer(10_000, 15_000, 9_000, 14_000)
      ),
      fighting(
        7,
        [
          %ScriptStep{
            command: :cast_spell,
            datalong: @magma_blast,
            target_type: :hostile_random,
            target_param1: @player
          }
        ],
        timer(3_000, 3_000, 2_500, 2_500) ++
          [condition: %Condition{type: :distance_to_target, value1: @hammer_reach, value2: @at_least}]
      ),
      event(8, :script_event, submerge(@say_servants),
        param1: @submerge_event,
        inverse_phase_mask: in_phases([@fighting])
      ),
      event(9, :script_event, submerge(@say_minions),
        param1: @submerge_event,
        inverse_phase_mask: in_phases([@emerged])
      ),
      event(10, :script_event, emerge(), param1: @emerge_event, inverse_phase_mask: in_phases([@submerged])),
      event(11, :summoned_just_died, [sons_slain()], param1: @son_of_flame, inverse_phase_mask: in_phases([@submerged]))
    ]
  end

  def events(_entry), do: []

  defp arrival do
    CreatureScript.timed([
      at(8_000, talk(@say_too_soon)),
      at(8_000, emote(@roar)),
      at(32_000, talk(@say_fool)),
      at(32_000, emote(@roar)),
      at(48_000, %ScriptStep{
        command: :cast_spell,
        datalong: @elemental_fire_kill,
        target_type: :nearest_creature_with_entry,
        target_param1: @majordomo,
        target_param2: 100
      })
    ])
  end

  defp submerge(text_id) do
    [
      %ScriptStep{command: :interrupt_casts},
      cast_self(@submerge, @triggered),
      cast_self(@submerge_visual, @triggered),
      talk(text_id),
      %ScriptStep{command: :stand_state, datalong: @custom_stand},
      phase(@submerged)
      | Enum.map(@sons, &son_of_flame/1)
    ] ++ [later(@emerge_after_ms, @emerge_event)]
  end

  defp emerge do
    surface() ++ [cast_self(@emerge), phase(@emerged), later(@submerge_after_ms, @submerge_event)]
  end

  defp surface do
    [
      %ScriptStep{command: :remove_aura, datalong: @submerge_visual},
      %ScriptStep{command: :remove_aura, datalong: @submerge},
      %ScriptStep{command: :stand_state, datalong: @stand}
    ]
  end

  defp son_of_flame(position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: @son_of_flame,
      datalong2: @son_lingers_ms,
      dataint3: @hostile_random,
      dataint4: @timed_out_of_combat,
      position: position
    }
  end

  defp sons_slain do
    %{
      send_self(@emerge_event)
      | condition: %Condition{type: :nearby_creature, value1: @son_of_flame, value2: @chamber, reverse?: true}
    }
  end

  defp dismiss_sons do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @despawn_script,
      datalong2: @creatures,
      datalong3: @son_of_flame,
      datalong4: @chamber,
      sub_scripts: %{@despawn_script => [%ScriptStep{command: :despawn}]}
    }
  end

  defp later(delay_ms, event_id), do: CreatureScript.timed([at(delay_ms, send_self(event_id))])

  defp send_self(event_id), do: %ScriptStep{command: :send_script_event, datalong: event_id, target_self?: true}

  defp forget_threat,
    do: %ScriptStep{command: :modify_threat, datalong: @all_attackers, position: {-100.0, 0.0, 0.0, 0.0}}

  defp fighting(index, steps, opts),
    do: event(index, :timer_in_combat, steps, [inverse_phase_mask: in_phases([@fighting, @emerged])] ++ opts)

  defp event(index, type, steps, opts \\ []), do: CreatureScript.event(@ragnaros, index, type, steps, opts)

  defp in_phases(phases), do: CreatureScript.only_in_phases(phases)
  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}

  defp timer(initial_min, initial_max, repeat_min, repeat_max),
    do: [param1: initial_min, param2: initial_max, param3: repeat_min, param4: repeat_max]

  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp emote(emote_id), do: %ScriptStep{command: :emote, datalong: emote_id}

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}
end
