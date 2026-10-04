defmodule ThistleTea.Game.Core.AI.CreatureScript.WailingCaverns do
  @moduledoc """
  vmangos `npc_disciple_of_naralex` and `npc_evolving_ectoplasm`: the ritual
  that wakes Naralex at the heart of Wailing Caverns.

  Once the four Fanglords lie dead (`InstanceScript.WailingCaverns`) the
  Disciple of Naralex offers to begin. He marks the party with the wild and
  leads them down through the caverns. Deviate Ravagers rush him at the first
  turn and he walks on once they are dead. At the serpent circle he chants a
  long cleansing, ignoring blows, while Deviate Vipers rise around him, and
  he moves on when the fight is over. Above Naralex's chamber he begins the
  awakening, which stuns him while the nightmare sends Deviate Moccasins,
  then Nightmare Ectoplasms, then Mutanus the Devourer. When Mutanus dies
  Naralex wakes, both druids take the form of owls, and they fly off. Every
  creature the ritual summons is a target of its map event, and they vanish
  if the disciple dies.

  The disciple sleeps an attacker every thirty seconds in a fight and drinks
  a potion when hurt. He keeps to his path the way a C++ escort does: he holds
  at each scene's point until it plays out, and fights back on the way.

  An Evolving Ectoplasm struck by frost, fire, nature, or shadow takes on
  that school's colour and becomes immune to it for ten seconds.

  Unlike vmangos, the summoned monsters attack the disciple at a run rather
  than walking to him, and he waits only for himself to leave combat, not
  the player who began the ritual, before leaving the serpent circle.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @disciple 3_678
  @naralex 3_679
  @ectoplasm 3_640
  @deviate_raptor 3_636
  @deviate_viper 5_755
  @deviate_moccasin 5_762
  @nightmare_ectoplasm 5_763
  @mutanus 3_654

  @disciple_field 4
  @mutanus_field 5
  @in_progress 1
  @done 3
  @special 4

  @mark_of_the_wild 5_232
  @sleep 1_090
  @potion 8_141
  @cleansing 6_270
  @awakening 6_271
  @owl_form 8_153

  @say_cast_mark 1_255
  @say_first_turn 1_256
  @say_after_raptors 1_257
  @say_before_circle 1_258
  @say_after_circle 1_259
  @say_before_chamber 1_263
  @say_before_ritual 1_264
  @emote_disciple_ritual 1_265
  @emote_naralex_troubled 1_268
  @emote_naralex_nightmare 1_269
  @say_attacked 1_273
  @say_mutanus_spawned 1_276
  @say_naralex_awakens 1_271
  @say_disciple_final 1_267
  @say_naralex_thanks 1_272
  @say_naralex_farewell 2_103

  @greeting_text 698
  @ready_text 699
  @begin_option "Let the event begin!"

  @path [
    {-134.9, 125.4, -78.1},
    {-125.6, 132.9, -78.4},
    {-113.8, 139.2, -80.9},
    {-109.8, 157.5, -80.2},
    {-108.6, 175.2, -79.7},
    {-108.6, 195.4, -80.6},
    {-111.0, 219.0, -86.5},
    {-102.4, 232.8, -91.5},
    {-82.4, 224.8, -93.5},
    {-73.4, 214.7, -93.2},
    {-67.7, 208.0, -93.3},
    {-43.3, 205.2, -96.3},
    {-34.6, 221.3, -95.8},
    {-32.5, 238.5, -93.5},
    {-42.1, 258.6, -92.8},
    {-54.0, 276.2, -92.8},
    {-48.6, 287.5, -92.4},
    {-47.2, 296.0, -90.8},
    {-35.6, 309.0, -89.7},
    {-23.5, 311.3, -88.6},
    {-8.6, 302.3, -87.4},
    {-1.2, 293.2, -85.5},
    {10.3, 279.2, -85.8},
    {23.1, 264.6, -86.6},
    {31.9, 251.4, -87.6},
    {43.3, 233.0, -87.6},
    {52.2, 208.7, -89.5},
    {78.7, 208.8, -92.8},
    {88.3, 225.2, -94.4},
    {98.7, 239.0, -95.8},
    {114.6, 236.9, -96.0},
    {114.6, 236.9, -96.0}
  ]

  @mark_point 0
  @first_turn 7
  @serpent_circle 15
  @chamber_overlook 26
  @ritual_point 30

  @raptor_spots [{-67.851196, 214.383102, -93.499001}, {-69.769707, 211.342804, -93.450737}]
  @viper_spots [{-52.9, 269.8, -92.8}, {-58.5, 279.8, -92.8}, {-49.6, 278.2, -92.8}]
  @mutanus_spot {142.7, 254.0, -102.2}
  @ectoplasm_spots [
    {142.7, 254.0, -102.2},
    {140.5, 219.8, -102.4},
    {92.2, 261.9, -101.5},
    {100.3, 268.6, -102.2},
    {123.8, 271.9, -102.4},
    {151.9, 234.3, -102.5},
    {127.6, 200.8, -101.8}
  ]
  @moccasin_spots [{123.8, 271.9, -102.4}, {151.9, 234.3, -102.5}, {127.6, 200.8, -101.8}]

  @flight [
    {33, {101.0, 239.2, -91.2}, -90.7},
    {34, {91.9, 233.6, -88.7}, -85.2},
    {35, {84.4, 218.1, -85.3}, -80.8},
    {36, {77.4, 208.2, -83.1}, -77.6},
    {37, {63.3, 205.4, -79.9}, -74.4},
    {38, {33.3, 201.4, -70.3}, -65.8}
  ]
  @flight_end 38

  @escorting 1
  @first_wave 2
  @cleansing_circle 3
  @after_circle 4
  @ritual 5
  @awaiting_mutanus 6
  @finale 7

  @hold_ms 1_800_000
  @overlook_ms 3_000
  @mark_ms 5_000
  @poll_ms 1_000
  @event_s 3_600
  @mark_reach 30
  @event_reach 100
  @summon_lifetime_ms 3_600_000

  @escort_faction 250
  @npc_flags_field 147
  @all_flags 0xFFFF_FFFF
  @remove_flags 2
  @players 3
  @summoner 8
  @dead_despawn 7
  @triggered 0x02
  @script_route 5
  @point_motion 9
  @inform 0x2
  @run 0x4
  @emote_talk 1
  @emote_point 25
  @sitting 1
  @standing 0
  @passive 0
  @aggressive 2
  @event_script 1
  @summon_script 1
  @cleanup_script 1

  @chamber_facing 6.24
  @first_turn_facing 5.86

  @ectoplasm_schools [
    {16, 7_944, 7_940},
    {4, 7_943, 7_942},
    {8, 7_945, 7_941},
    {32, 7_946, 7_743}
  ]
  @ectoplasm_immune 1
  @ectoplasm_immunity_ms 10_000

  def disciple, do: @disciple

  @impl CreatureScript
  def entries, do: [@disciple, @ectoplasm]

  @impl CreatureScript
  def events(@disciple = entry) do
    fighting = CreatureScript.only_in_phases([0, @escorting, @first_wave, @after_circle])

    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast(@sleep, :hostile_random_not_top)],
        param1: 5_000,
        param2: 5_000,
        param3: 30_000,
        param4: 30_000,
        inverse_phase_mask: fighting
      ),
      CreatureScript.event(entry, 2, :hp, [cast_self(@potion, 0)],
        param1: 80,
        param2: 0,
        param3: 45_000,
        param4: 45_000
      ),
      CreatureScript.event(entry, 3, :aggro, [talk(@say_attacked)], inverse_phase_mask: fighting),
      CreatureScript.event(entry, 4, :death, [end_event(false)]),
      CreatureScript.event(entry, 5, :timer_ooc, after_raptors(),
        param1: @poll_ms,
        param2: @poll_ms,
        param3: @poll_ms,
        param4: @poll_ms,
        inverse_phase_mask: CreatureScript.only_in_phases([@first_wave]),
        condition: summons_dead()
      ),
      CreatureScript.event(entry, 6, :timer_ooc, after_circle(),
        param1: @poll_ms,
        param2: @poll_ms,
        param3: @poll_ms,
        param4: @poll_ms,
        inverse_phase_mask: CreatureScript.only_in_phases([@after_circle]),
        condition: summons_dead()
      ),
      mutanus_slain(entry, 7, :timer_ooc),
      mutanus_slain(entry, 8, :timer_in_combat)
    ] ++ flight_events(entry)
  end

  def events(@ectoplasm = entry) do
    schools =
      @ectoplasm_schools
      |> Enum.with_index(1)
      |> Enum.map(fn {{school_mask, transform, immunity}, index} ->
        CreatureScript.event(
          entry,
          index,
          :hit_by_spell,
          [
            cast_self(transform, @triggered),
            cast_self(immunity, @triggered),
            phase(@ectoplasm_immune),
            CreatureScript.timed(Enum.map([phase(0) | clear_colours()], &at(@ectoplasm_immunity_ms, &1)))
          ],
          param2: school_mask,
          inverse_phase_mask: CreatureScript.only_in_phases([0])
        )
      end)

    schools ++ [CreatureScript.event(entry, 5, :evade, [phase(0) | clear_colours()])]
  end

  @impl CreatureScript
  def gossip do
    ready = %Condition{type: :instance_data, value1: @disciple_field, value2: @special}

    %{
      @disciple => %Gossip{
        texts: [%Gossip.Text{text_id: @greeting_text}, %Gossip.Text{text_id: @ready_text, condition: ready}],
        options: [%Gossip.Option{text: @begin_option, condition: ready, steps: begin()}]
      }
    }
  end

  @impl CreatureScript
  def routes do
    [%Route{entry: @disciple, path: path(), points: points()}]
  end

  defp begin do
    [
      %ScriptStep{command: :start_map_event, datalong: @disciple, datalong2: @event_s},
      CreatureScript.faction(@escort_faction),
      %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: @all_flags, datalong3: @remove_flags},
      %ScriptStep{command: :set_run, datalong: 0},
      phase(@escorting),
      resume(0)
    ]
  end

  defp path do
    waits = %{
      @mark_point => @mark_ms,
      @first_turn => @hold_ms,
      @serpent_circle => @hold_ms,
      @chamber_overlook => @overlook_ms,
      @ritual_point => @hold_ms
    }

    @path
    |> Enum.with_index()
    |> Enum.map(fn {{x, y, z}, index} -> {x, y, z, Map.get(waits, index, 0)} end)
  end

  defp points do
    %{
      @mark_point => [talk(@say_cast_mark), emote(@emote_talk), CreatureScript.timed([at(@mark_ms, mark_party())])],
      @first_turn => first_turn(),
      @serpent_circle => serpent_circle(),
      @chamber_overlook => [face_angle(@chamber_facing), talk(@say_before_chamber), emote(@emote_point)],
      @ritual_point => ritual()
    }
  end

  defp mark_party do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @event_script,
      datalong2: @players,
      datalong4: @mark_reach,
      target_self?: true,
      sub_scripts: %{
        @event_script => [
          %ScriptStep{command: :cast_spell, datalong: @mark_of_the_wild, swap_final?: true, condition: alive()}
        ]
      }
    }
  end

  defp first_turn do
    [
      talk(@say_first_turn),
      emote(@emote_talk),
      CreatureScript.timed(
        [at(6_000, face_angle(@first_turn_facing)) | Enum.map(@raptor_spots, &at(6_000, summon(@deviate_raptor, &1)))] ++
          [at(8_000, phase(@first_wave))]
      )
    ]
  end

  defp after_raptors do
    [
      phase(@escorting),
      talk(@say_after_raptors),
      emote(@emote_point),
      CreatureScript.timed([at(5_000, resume(@first_turn + 1))])
    ]
  end

  defp serpent_circle do
    [
      phase(@cleansing_circle),
      talk(@say_before_circle),
      emote(@emote_talk),
      CreatureScript.timed(
        [
          at(2_000, %ScriptStep{command: :set_react_state, datalong: @passive}),
          at(2_000, cast_self(@cleansing, 0))
        ] ++
          Enum.map(@viper_spots, &at(17_000, summon(@deviate_viper, &1))) ++
          [
            at(33_000, %ScriptStep{command: :set_react_state, datalong: @aggressive}),
            at(33_000, phase(@after_circle))
          ]
      )
    ]
  end

  defp after_circle do
    [
      phase(@escorting),
      talk(@say_after_circle),
      emote(@emote_talk),
      CreatureScript.timed([at(2_000, resume(@serpent_circle + 1))])
    ]
  end

  defp ritual do
    [
      phase(@ritual),
      instance_data(@disciple_field, @in_progress),
      face(@naralex),
      CreatureScript.timed(
        [
          at(1_000, face(@naralex)),
          at(1_000, talk(@say_before_ritual)),
          at(1_000, emote(@emote_talk)),
          at(3_000, cast_self(@awakening, 0)),
          at(3_000, talk(@emote_disciple_ritual)),
          at(3_000, emote(@emote_talk)),
          at(7_000, by(@naralex, talk(@emote_naralex_troubled))),
          at(7_000, by(@naralex, emote(@emote_talk)))
        ] ++
          Enum.map(@moccasin_spots, &at(12_000, summon(@deviate_moccasin, &1))) ++
          Enum.map(@ectoplasm_spots, &at(52_000, summon(@nightmare_ectoplasm, &1))) ++
          [
            at(92_000, by(@naralex, talk(@emote_naralex_nightmare))),
            at(92_000, by(@naralex, emote(@emote_talk))),
            at(92_000, emote(@emote_talk)),
            at(102_000, summon(@mutanus, @mutanus_spot)),
            at(104_000, talk_to(@say_mutanus_spawned, @mutanus)),
            at(104_000, phase(@awaiting_mutanus))
          ]
      )
    ]
  end

  defp naralex_wakes do
    {33, disciple_spot, naralex_z} = hd(@flight)

    [
      phase(@finale),
      by(@naralex, stand(@sitting)),
      by(@naralex, talk(@say_naralex_awakens)),
      by(@naralex, emote(@emote_talk)),
      %ScriptStep{command: :interrupt_casts},
      %ScriptStep{command: :remove_aura, datalong: @awakening},
      instance_data(@disciple_field, @done),
      end_event(true),
      CreatureScript.timed([
        at(2_000, talk(@say_disciple_final)),
        at(2_000, emote(@emote_talk)),
        at(7_000, by(@naralex, talk(@say_naralex_thanks))),
        at(7_000, by(@naralex, emote(@emote_talk))),
        at(7_000, by(@naralex, stand(@standing))),
        at(15_000, by(@naralex, talk(@say_naralex_farewell))),
        at(15_000, by(@naralex, emote(@emote_talk))),
        at(15_000, cast_self(@owl_form, 0)),
        at(15_000, by(@naralex, cast_self(@owl_form, 0))),
        at(23_000, %ScriptStep{command: :set_fly, datalong: 1}),
        at(23_000, by(@naralex, %ScriptStep{command: :set_fly, datalong: 1})),
        at(23_000, fly(disciple_spot, 33)),
        at(23_000, by(@naralex, fly(put_elem(disciple_spot, 2, naralex_z), 0)))
      ])
    ]
  end

  defp mutanus_slain(entry, index, timer) do
    CreatureScript.event(entry, index, timer, naralex_wakes(),
      param1: @poll_ms,
      param2: @poll_ms,
      param3: @poll_ms,
      param4: @poll_ms,
      inverse_phase_mask: CreatureScript.only_in_phases([@awaiting_mutanus]),
      condition: %Condition{type: :instance_data, value1: @mutanus_field, value2: @done}
    )
  end

  defp flight_events(entry) do
    @flight
    |> Enum.zip(tl(@flight))
    |> Enum.with_index(10)
    |> Enum.map(fn {{{point, _spot, _naralex_z}, {next, spot, naralex_z}}, index} ->
      CreatureScript.event(
        entry,
        index,
        :movement_inform,
        [fly(spot, next), by(@naralex, fly(put_elem(spot, 2, naralex_z), 0))],
        param1: @point_motion,
        param2: point
      )
    end)
    |> Kernel.++([
      CreatureScript.event(
        entry,
        20,
        :movement_inform,
        [by(@naralex, %ScriptStep{command: :despawn}), %ScriptStep{command: :despawn}],
        param1: @point_motion,
        param2: @flight_end
      )
    ])
  end

  defp summon(entry, {x, y, z}) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @summon_lifetime_ms,
      dataint2: @summon_script,
      dataint3: @summoner,
      dataint4: @dead_despawn,
      position: {x, y, z, 0.0},
      sub_scripts: %{
        @summon_script => [
          %ScriptStep{
            command: :add_map_event_target,
            datalong: @disciple,
            dataint4: @cleanup_script,
            sub_scripts: %{@cleanup_script => [%ScriptStep{command: :despawn, condition: alive()}]}
          }
        ]
      }
    }
  end

  defp summons_dead do
    %Condition{type: :map_event_targets, value1: @disciple, children: [%{alive() | reverse?: true}]}
  end

  defp clear_colours do
    Enum.flat_map(@ectoplasm_schools, fn {_school, transform, immunity} ->
      [%ScriptStep{command: :remove_aura, datalong: transform}, %ScriptStep{command: :remove_aura, datalong: immunity}]
    end)
  end

  defp resume(point), do: %ScriptStep{command: :start_waypoints, datalong: @script_route, datalong2: point}

  defp end_event(success?),
    do: %ScriptStep{command: :end_map_event, datalong: @disciple, datalong2: if(success?, do: 1, else: 0)}

  defp fly({x, y, z}, 0), do: %ScriptStep{command: :move_to, datalong3: @run, position: {x, y, z, 0.0}}

  defp fly({x, y, z}, point),
    do: %ScriptStep{command: :move_to, datalong3: @run, datalong4: @inform, dataint: point, position: {x, y, z, 0.0}}

  defp by(entry, %ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @event_reach,
        swap_final?: true
    }
  end

  defp face(entry) do
    %ScriptStep{
      command: :turn_to,
      target_type: :nearest_creature_with_entry,
      target_param1: entry,
      target_param2: @event_reach
    }
  end

  defp talk_to(text_id, entry) do
    %{talk(text_id) | target_type: :nearest_creature_with_entry, target_param1: entry, target_param2: @event_reach}
  end

  defp cast(spell_id, target_type), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: target_type}

  defp cast_self(spell_id, flags),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp instance_data(field, value), do: %ScriptStep{command: :set_instance_data, datalong: field, datalong2: value}
  defp face_angle(angle), do: %ScriptStep{command: :turn_to, datalong: 1, position: {0.0, 0.0, 0.0, angle}}
  defp emote(emote_id), do: %ScriptStep{command: :emote, datalong: emote_id}
  defp stand(stand_state), do: %ScriptStep{command: :stand_state, datalong: stand_state}
  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}
  defp alive, do: %Condition{type: :alive}
end
