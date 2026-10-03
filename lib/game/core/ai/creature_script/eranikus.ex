defmodule ThistleTea.Game.Core.AI.CreatureScript.Eranikus do
  @moduledoc """
  vmangos `boss_eranikus` and the fighting half of `npc_keeper_remulos`: The
  Nightmare Manifests, where Keeper Remulos pulls Eranikus, Tyrant of the
  Dream, out of a rift over Lake Elun'ara and Tyrande Whisperwind redeems
  him.

  Remulos's escort (`Core.Quest.QuestEscort.Catalog`) summons Eranikus over
  the lake. He hovers there out of reach, flies up over the shrine when
  Remulos signals `fly_up/0`, and once the waves of Nightmare Phantasms are
  spent and Remulos signals `descend/0` he lands before the shrine and goes
  for Remulos. He never moves in combat. He breathes Noxious and Acid Breath
  at his victim and looses Shadow Bolt Volleys. As his health falls he
  taunts, and at 85 percent Tyrande rides in from the north with seven
  Priestesses of the Moon, who join the fight while she channels her
  absolution. He cannot fall below 20 percent: there he is redeemed. He
  turns friendly, the fighting stops, Tyrande kneels, the Light of Elune
  takes him back into his night elf form, and he thanks the heroes. Remulos
  then credits the quest for the escorting player's group and leaves for
  his grove. Eranikus joins the quest's map event, so if the escort fails,
  or he evades before his redemption, he and every helper and phantasm
  around him go away. Remulos heals the wounded and casts Starfire only
  while the escort's event phase is set.

  Tyrande rides straight to the shrine instead of along the bridge points
  vmangos walks her through, the priestesses turn on Eranikus thirty seconds
  after they appear rather than once they reach her, and the world-wide
  redemption announcement is a zone-wide boss emote. Eranikus does not shift
  his threat toward attackers he can reach.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @quest 8736

  @remulos 11_832
  @eranikus 15_491
  @tyrande 15_633
  @priestess 15_634
  @phantasm 15_629

  @say_landing 11_305
  @say_taunt 11_306
  @say_kill 11_027
  @say_burning 11_314
  @say_why 11_315
  @say_redeeming 11_316
  @emote_redeemed 11_313
  @say_saved 11_323
  @say_return 11_324
  @say_unworthy 11_326
  @say_heroes 11_327
  @say_tyrande_arrives 11_309
  @say_tyrande_heal 11_317
  @say_absolution 11_310
  @say_forgiven 11_311
  @say_cannot_channel 11_312
  @emote_kneel 11_319
  @say_praise 11_320
  @say_it_will_be_done 11_303
  @say_leave_nighthaven 11_329

  @hover 17_131
  @noxious_breath 24_818
  @acid_breath 24_839
  @shadow_bolt_volley 25_586
  @arcane_channeling 23_017
  @night_elf_form 25_846
  @frostsaber 16_056
  @healing_touch 23_381
  @rejuvenation 20_664
  @regrowth 20_665
  @starfire 21_668

  @flight {7929.86, -2574.88, 505.35}
  @landing {7912.98, -2568.99, 488.71}
  @redemption {7906.57, -2565.63, 488.39}
  @tyrande_arrival {7955.826172, -2369.380856, 486.537537, 4.812577}
  @tyrande_kneel {7888.32, -2566.25, 487.02}
  @tyrande_channel {7901.83, -2565.24, 488.04}

  @fly_up 1
  @descend 2
  @flight_point 10
  @landing_point 11
  @redemption_point 12
  @kneel_point 5
  @channel_point 6
  @point_motion 9

  @fighting 0
  @redeemed 1
  @nightmare 1

  @friendly 35
  @not_attackable 0x2
  @pacified 0x0002_0000
  @pvp 0x1000
  @unit_flags_field 46
  @set_flags 1
  @remove_flags 2
  @triggered 0x02
  @pathfind 0x01
  @run 0x04
  @fly 0x08
  @point_movement 0x02
  @summon_run 0x01
  @no_attack -1
  @corpse_despawn 5
  @percent 1
  @players_only 1
  @creatures 2
  @boss_emote 3
  @land 293
  @bow 2
  @standing 0
  @dead 7
  @kneeling 8
  @shrine_radius 250
  @priestess_script 1
  @priestess_ride_ms 30_000
  @escort_faction 495
  @random_point 3
  @credit_distance 100
  @heal_radius 40
  @injured 1
  @cleanup_script 1
  @for_all_script 1
  @event_success 1
  @event_failure 0

  def fly_up, do: @fly_up
  def descend, do: @descend
  def nightmare_phase, do: @nightmare

  @impl CreatureScript
  def entries, do: [@remulos, @eranikus, @tyrande]

  @impl CreatureScript
  def events(@remulos) do
    heals = CreatureScript.pick([[heal(@healing_touch)], [heal(@rejuvenation)], [heal(@regrowth)]])

    [
      nightmare(1, :timer_in_combat, heals, timer(10_000, 10_000)),
      nightmare(
        2,
        :timer_in_combat,
        [%ScriptStep{command: :cast_spell, datalong: @starfire, target_type: :hostile_random}],
        timer(25_000, 20_000)
      )
    ]
  end

  def events(@eranikus) do
    [
      event(@eranikus, 1, :spawned, rift()),
      event(@eranikus, 2, :script_event, [fly_to(@flight, @flight_point)], param1: @fly_up),
      event(@eranikus, 3, :movement_inform, [face(@remulos)], param1: @point_motion, param2: @flight_point),
      event(@eranikus, 4, :script_event, [remove_aura(@hover), fly_to(@landing, @landing_point)], param1: @descend),
      event(@eranikus, 5, :movement_inform, landing(), param1: @point_motion, param2: @landing_point),
      event(@eranikus, 6, :aggro, [set_combat_movement(false)]),
      event(@eranikus, 7, :kill, [talk(@say_kill)], param3: @players_only),
      fighting(8, :timer_in_combat, [cast_victim(@noxious_breath)], timer(3_000, 30_000)),
      fighting(9, :timer_in_combat, [cast_self(@shadow_bolt_volley)], timer(5_000, 25_000)),
      fighting(10, :timer_in_combat, [cast_victim(@acid_breath)], timer(10_000, 15_000)),
      fighting(11, :evade, [%ScriptStep{command: :end_map_event, datalong: @quest, datalong2: @event_failure}]),
      health(12, 85, [talk(@say_taunt), tyrande(), CreatureScript.timed([at(3_000, priestesses())])]),
      health(13, 75, [talk(@say_taunt)]),
      health(14, 35, [talk(@say_burning)]),
      health(15, 31, [by(@tyrande, talk(@say_forgiven))]),
      health(16, 27, [by(@tyrande, talk(@say_cannot_channel))]),
      health(17, 25, [talk(@say_why)]),
      health(18, 20, redemption()),
      event(@eranikus, 19, :movement_inform, farewell(),
        param1: @point_motion,
        param2: @redemption_point,
        inverse_phase_mask: CreatureScript.only_in_phases([@redeemed])
      )
    ]
  end

  def events(@tyrande) do
    [
      event(@tyrande, 1, :spawned, [talk(@say_tyrande_arrives), ride_to(@tyrande_kneel, @kneel_point)]),
      event(
        @tyrande,
        2,
        :movement_inform,
        [
          talk(@say_tyrande_heal),
          remove_aura(@frostsaber),
          CreatureScript.timed([at(5_000, move_to(@tyrande_channel, @pathfind, @channel_point))])
        ],
        param1: @point_motion,
        param2: @kneel_point
      ),
      event(@tyrande, 3, :movement_inform, [cast_self(@arcane_channeling), talk(@say_absolution)],
        param1: @point_motion,
        param2: @channel_point
      )
    ]
  end

  defp rift do
    [
      %ScriptStep{command: :add_aura, datalong: @hover},
      set_fly(true),
      unit_flags(@not_attackable, @set_flags),
      %ScriptStep{command: :invincibility, datalong: 20, datalong2: @percent},
      %ScriptStep{
        command: :add_map_event_target,
        datalong: @quest,
        dataint4: @cleanup_script,
        sub_scripts: %{@cleanup_script => [for_all(@tyrande, [despawn()]) | dismiss_helpers()] ++ [despawn()]}
      }
    ]
  end

  defp landing do
    [
      set_fly(false),
      %ScriptStep{command: :emote, datalong: @land},
      talk(@say_landing),
      %ScriptStep{command: :set_home_position, datalong: 1},
      CreatureScript.timed([
        at(1_000, unit_flags(@not_attackable, @remove_flags)),
        at(1_000, %ScriptStep{command: :set_run, datalong: 0}),
        at(1_000, attack(@remulos))
      ])
    ]
  end

  defp tyrande do
    %ScriptStep{
      command: :summon_creature,
      datalong: @tyrande,
      dataint3: @no_attack,
      dataint4: @corpse_despawn,
      position: @tyrande_arrival
    }
  end

  defp priestesses do
    {x, y, z} = @tyrande_kneel

    %ScriptStep{
      command: :summon_creature,
      datalong: @priestess,
      dataint: @summon_run,
      dataint2: @priestess_script,
      dataint3: @no_attack,
      dataint4: @corpse_despawn,
      position: @tyrande_arrival,
      count: 7,
      scatter: 10.0,
      sub_scripts: %{
        @priestess_script => [
          CreatureScript.faction(@escort_faction),
          %ScriptStep{
            command: :move_to,
            datalong: @random_point,
            datalong3: @pathfind + @run,
            position: {x, y, z, 5.0}
          },
          at(@priestess_ride_ms, attack(@eranikus))
        ]
      }
    }
  end

  defp redemption do
    [
      %ScriptStep{command: :set_phase, datalong: @redeemed},
      talk(@say_redeeming),
      %ScriptStep{command: :clear_auras},
      CreatureScript.faction(@friendly),
      unit_flags(@not_attackable ||| @pacified, @set_flags),
      %ScriptStep{command: :combat_stop},
      for_all(@remulos, [%ScriptStep{command: :combat_stop}])
    ] ++
      dismiss_helpers() ++
      [
        CreatureScript.timed([
          at(5_000, by(@tyrande, %ScriptStep{command: :interrupt_casts})),
          at(5_000, by(@tyrande, stand(@kneeling))),
          at(5_000, by(@tyrande, talk(@emote_kneel))),
          at(5_000, %{talk(@emote_redeemed) | datalong: @boss_emote}),
          at(5_000, stand(@dead)),
          at(10_000, by(@tyrande, talk(@say_praise))),
          at(16_000, cast_self(@night_elf_form, @triggered)),
          at(21_000, stand(@standing)),
          at(21_000, move_to(@redemption, @pathfind, @redemption_point))
        ])
      ]
  end

  defp farewell do
    [
      talk(@say_saved),
      CreatureScript.timed([
        at(11_000, talk(@say_return)),
        at(22_000, talk(@say_unworthy)),
        at(35_000, talk(@say_heroes)),
        at(42_000, by(@tyrande, stand(@standing))),
        at(42_000, by(@tyrande, despawn(9_000))),
        at(42_000, for_all(@remulos, remulos_outro())),
        at(42_000, %ScriptStep{command: :emote, datalong: @bow}),
        at(42_000, despawn(2_000))
      ])
    ]
  end

  defp remulos_outro do
    [
      %ScriptStep{
        command: :quest_explored,
        datalong: @quest,
        datalong2: @credit_distance,
        datalong3: 1,
        target_type: :map_event_target,
        target_param1: @quest
      },
      unit_flags(@pvp, @remove_flags),
      at(3_000, talk(@say_it_will_be_done)),
      at(6_000, talk(@say_leave_nighthaven)),
      at(6_000, %ScriptStep{command: :end_map_event, datalong: @quest, datalong2: @event_success}),
      at(6_000, %ScriptStep{command: :despawn, datalong2: 1})
    ]
  end

  defp dismiss_helpers, do: [for_all(@priestess, [despawn()]), for_all(@phantasm, [despawn()])]

  defp heal(spell_id) do
    %ScriptStep{
      command: :cast_spell,
      datalong: spell_id,
      target_type: :friendly_injured,
      target_param1: @heal_radius,
      target_param2: @injured
    }
  end

  defp nightmare(index, event_type, steps, opts),
    do:
      event(
        @remulos,
        index,
        event_type,
        steps,
        [inverse_phase_mask: CreatureScript.only_in_phases([@nightmare])] ++ opts
      )

  defp fighting(index, event_type, steps, opts \\ []),
    do:
      event(
        @eranikus,
        index,
        event_type,
        steps,
        [inverse_phase_mask: CreatureScript.only_in_phases([@fighting])] ++ opts
      )

  defp health(index, health_pct, steps), do: fighting(index, :hp, steps, param1: health_pct, repeatable?: false)

  defp event(entry, index, event_type, steps, opts \\ []),
    do: CreatureScript.event(entry, index, event_type, steps, opts)

  defp timer(initial_ms, repeat_ms), do: [param1: initial_ms, param2: initial_ms, param3: repeat_ms, param4: repeat_ms]

  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}

  defp by(entry, %ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @shrine_radius,
        swap_final?: true
    }
  end

  defp for_all(entry, steps) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @for_all_script,
      datalong2: @creatures,
      datalong3: entry,
      datalong4: @shrine_radius,
      sub_scripts: %{@for_all_script => steps}
    }
  end

  defp attack(entry) do
    %ScriptStep{
      command: :attack_start,
      target_type: :nearest_creature_with_entry,
      target_param1: entry,
      target_param2: @shrine_radius
    }
  end

  defp face(entry) do
    %ScriptStep{
      command: :turn_to,
      target_type: :nearest_creature_with_entry,
      target_param1: entry,
      target_param2: @shrine_radius
    }
  end

  defp fly_to(position, point), do: move_to(position, @run + @fly, point)
  defp ride_to(position, point), do: move_to(position, @pathfind + @run, point)

  defp move_to({x, y, z}, options, point) do
    %ScriptStep{
      command: :move_to,
      datalong3: options,
      datalong4: @point_movement,
      dataint: point,
      position: {x, y, z, 0.0}
    }
  end

  defp unit_flags(mask, mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: mask, datalong3: mode}

  defp set_fly(enabled?), do: %ScriptStep{command: :set_fly, datalong: if(enabled?, do: 1, else: 0)}

  defp set_combat_movement(enabled?),
    do: %ScriptStep{command: :set_combat_movement, datalong: if(enabled?, do: 1, else: 0)}

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp remove_aura(spell_id), do: %ScriptStep{command: :remove_aura, datalong: spell_id}
  defp stand(stand_state), do: %ScriptStep{command: :stand_state, datalong: stand_state}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp despawn(delay_ms \\ 0), do: %ScriptStep{command: :despawn, datalong: delay_ms}
end
