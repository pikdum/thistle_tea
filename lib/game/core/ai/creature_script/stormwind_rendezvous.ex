defmodule ThistleTea.Game.Core.AI.CreatureScript.StormwindRendezvous do
  @moduledoc """
  vmangos `npc_squire_rowe` and `npc_reginald_windsor`: The Great Masquerade
  (6403), where Reginald Windsor marches through Stormwind and unmasks Lady
  Katrana Prestor as Onyxia.

  A player who has finished Stormwind Rendezvous (6402) asks Squire Rowe at
  the city gates to signal Windsor. Rowe runs out to the road, kneels, sets
  off a flare, and Windsor rides in. Windsor dismisses his horse Mercutio,
  greets the player, and takes the rendezvous. The rendezvous map event
  (keyed by 6402) stands while Windsor is up, so Rowe tells others he is
  busy, and its player is the one Windsor greets. Windsor leaves if no one
  takes The Great Masquerade within five minutes.

  Taking The Great Masquerade starts its own map event, which fails the
  quest and sends Windsor away if he dies or the player strays. Six city
  guards line the bridge into the city and General Marcus Jonathan bars the
  way. Windsor walks to the bridge and talks Marcus down, the guards kneel,
  and Windsor walks on toward the keep. City guards, patrollers, and royal
  guards near him along the way salute him. Short of the keep he waits for
  the player's word, then walks into the throne room. There he reads the
  tablets that reveal Katrana Prestor as Lady Onyxia. The royal guards
  around her become Onyxia's Elite Guards, she strikes Windsor down, and she
  vanishes while her guards fall on Bolvar Fordragon. Once no elite guard
  is left standing, Bolvar apologizes, the quest is credited to the player's
  group, and Windsor dies.

  Unlike vmangos, guards salute Windsor as he reaches each point on his
  walk, not as they come within reach, and the six bridge guards each find
  their kneeling spot from where they were summoned. The finale waits for
  the elite guards to fall rather than for Bolvar to leave combat.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @rendezvous 6_402
  @masquerade 6_403

  @rowe 17_804
  @windsor 12_580
  @mercutio 12_581
  @marcus 466
  @anduin 1_747
  @bolvar 1_748
  @prestor 1_749
  @lady_onyxia 12_756
  @elite_guard 12_739
  @city_guard 68
  @patroller 1_976
  @royal_guard 1_756
  @flare 181_987

  @say_signal_sent 14_389
  @say_hiss 8_245
  @say_dismiss_horse 8_091
  @say_greeting 8_090
  @say_on_guard 8_107
  @say_justice 8_109
  @say_seize_him 8_119
  @say_marcus_cannot 8_121
  @say_turalyon 8_123
  @say_not_right 8_133
  @say_marcus_lost 8_124
  @say_marcus_ashamed 8_125
  @say_marcus_shame 8_132
  @say_vigilant 8_126
  @say_stand_down 8_134
  @say_heroes_walk 8_127
  @say_move_aside 8_128
  @say_not_harmed 8_129
  @say_marcus_go 8_130
  @say_thank_you 8_205
  @say_to_the_keep 8_206
  @say_be_brave 8_207
  @say_onward 8_208
  @say_run_majesty 8_210
  @say_safe_hall 8_212
  @say_masquerade_over 8_211
  @say_prestor_laughs 8_214
  @say_incarcerated 8_215
  @say_limp_body 8_216
  @say_prophesied 8_218
  @say_tablets 8_226
  @say_not_coding 8_227
  @say_listen_dragon 8_219
  @say_reads 8_228
  @say_bolvar_gasps 8_236
  @say_curious 8_235
  @say_dragon_filth 8_237
  @say_onyxia_laughs 8_238
  @say_come_to_aid 8_239
  @say_do_not_let_her_escape 8_247
  @say_was_this_fated 8_246
  @say_farewell 8_248
  @say_medallion_shatters 8_266
  @say_sorry 8_249
  @say_use_the_medallion 8_250
  @say_dies 8_251
  @guard_salutes [8_167, 8_170, 8_172, 8_175, 8_177, 8_180, 8_183, 8_184]

  @rowe_nothing 9_063
  @rowe_busy 9_064
  @rowe_ready 9_065
  @rowe_completed 9_066
  @windsor_menu 5_633
  @signal_option "Let Marshal Windsor know that I am ready."
  @ready_option "I am ready, as are my forces. Let us end this masquerade!"

  @dismiss_horse 20_000
  @read_tablets 20_358
  @windsor_death 20_465
  @prestor_despawns 20_466

  @rowe_home {-9_042.23, 434.241, 93.2955, 2.234}
  @rowe_road {-9_058.07, 441.32, 93.06, 3.84}
  @rowe_signal {-9_084.88, 419.23, 92.42, 3.83}
  @flare_position {-9_095.839844, 411.178986, 92.244499, 2.303830}
  @windsor_summon {-9_148.40, 371.32, 91.0, 0.70}
  @mercutio_pasture {-9_148.395508, 371.322174, 90.543655, 0.0}
  @prestor_voice {-9_075.6, 466.11, 120.383, 6.27}
  @bolvar_rest {-8_447.39, 335.35, 121.747, 1.29}
  @bolvar_spawn {-8_439.98, 329.392, 122.579, 2.293}
  @anduin_spawn {-8_439.7, 331.012, 122.763, 2.23402}

  @city_gate {-9_050.406250, 443.974792, 93.056458, 0.659825}
  @procession [
    {-8_968.008789, 509.771759, 96.350754},
    {-8_954.638672, 519.920410, 96.355453},
    {-8_933.738281, 500.683533, 93.842247},
    {-8_923.248047, 496.464294, 93.858475},
    {-8_907.830078, 509.035645, 93.842529},
    {-8_927.302734, 542.173523, 94.291695},
    {-8_825.773438, 623.565918, 93.838066},
    {-8_795.209961, 590.400269, 97.495560},
    {-8_769.717773, 608.193298, 97.130692},
    {-8_736.326172, 574.955811, 97.385048},
    {-8_749.043945, 560.525330, 97.400307},
    {-8_730.701172, 540.466370, 101.105370},
    {-8_713.182617, 519.765442, 97.185402},
    {-8_673.321289, 554.135986, 97.267708},
    {-8_651.262695, 551.696045, 97.002983},
    {-8_618.138672, 518.573425, 103.123642},
    {-8_566.013672, 465.536804, 104.597160},
    {-8_548.403320, 466.680695, 104.533554}
  ]
  @keep [
    {-8_529.294922, 443.376495, 104.917046},
    {-8_507.087891, 415.847321, 108.385857},
    {-8_486.496094, 389.750427, 108.590248},
    {-8_455.687500, 351.054321, 120.885910},
    {-8_446.392578, 339.602783, 121.329506}
  ]

  @marcus_post {-8_964.973633, 512.194519, 96.355247, 3.835189}
  @marcus_kneel {-8_976.549805, 514.405701, 96.590057, 5.388790}
  @bridge_guards [
    {{-8_963.196289, 510.056549, 96.355240, 3.835189}, {-8_958.585938, 506.907959, 96.595634, 2.294317}},
    {{-8_961.235352, 507.696808, 96.595337, 3.835189}, {-8_960.827148, 505.079407, 96.593971, 2.255047}},
    {{-8_959.596680, 505.725403, 96.595490, 3.835189}, {-8_962.866211, 503.415009, 96.591331, 2.255047}},
    {{-8_967.410156, 515.123535, 96.354881, 3.835189}, {-8_969.562500, 520.014587, 96.595673, 5.388790}},
    {{-8_968.840820, 516.844482, 96.595253, 3.835189}, {-8_971.773438, 518.239868, 96.594200, 5.388790}},
    {{-8_970.687500, 519.065796, 96.595245, 3.835189}, {-8_973.923828, 516.513611, 96.590904, 5.475183}}
  ]
  @safe_hall {-8_506.340820, 338.364441, 120.88584, 6.219385}
  @bolvar_guard_post {-8_449.006836, 337.693451, 121.32955, 5.740616}

  @point_motion 9
  @signal_road 1
  @signal_point 2
  @rowe_home_point 4
  @at_city_gate 1
  @procession_route 1
  @keep_route 2
  @script_route 5

  @waiting 1
  @marching 2
  @holding_the_line 3
  @finale 4

  @gossip_flag 0x1
  @questgiver_flag 0x2
  @all_flags 0xFFFF_FFFF
  @npc_flags_field 147
  @unit_flags_field 46
  @set_flags 1
  @remove_flags 2
  @not_attackable 0x2
  @immune_to_npc 0x200
  @not_selectable 0x0200_0000
  @bolvar_combat_faction 11
  @restore_on_combat_stop 0x02
  @invisible_model 11_686
  @windsor_mount 2_410
  @is_display_id 1

  @pathfind 0x1
  @walk 0x2
  @run 0x4
  @inform 0x2
  @triggered 0x02
  @no_attack -1
  @timed_despawn 3
  @manual_despawn 8
  @creatures 2
  @incomplete 1
  @complete 2
  @source_dead 1
  @for_all_script 1
  @summon_script 1
  @cleanup_script 1
  @failure_script 1

  @emote_kneel 16
  @emote_salute 66
  @standing 0
  @dead 7
  @kneeling 8

  @walk_yards_per_s 2.5
  @event_reach 150
  @salute_reach 10
  @bridge_reach 15
  @royal_guard_reach 25
  @elite_guard_reach 35
  @bolvar_reach 60
  @spot_reach 1.0
  @windsor_s 5_400
  @rendezvous_s 2_400
  @masquerade_s 1_800
  @max_distance 100
  @idle_ms 300_000
  @poll_ms 2_000
  @corpse_ms 420_000
  @onyxia_respawn_s 1_800

  def rendezvous, do: @rendezvous
  def masquerade, do: @masquerade

  @impl CreatureScript
  def entries, do: [@rowe, @windsor]

  @impl CreatureScript
  def events(@rowe = entry) do
    [
      CreatureScript.event(entry, 1, :movement_inform, [move(@rowe_signal, @run, @signal_point)],
        param1: @point_motion,
        param2: @signal_road
      ),
      CreatureScript.event(entry, 2, :movement_inform, signal_windsor(),
        param1: @point_motion,
        param2: @signal_point
      ),
      CreatureScript.event(entry, 3, :movement_inform, back_at_post(),
        param1: @point_motion,
        param2: @rowe_home_point
      )
    ]
  end

  def events(@windsor = entry) do
    [
      CreatureScript.event(entry, 1, :movement_inform, greet(), param1: @point_motion, param2: @at_city_gate),
      CreatureScript.event(entry, 2, :timer_ooc, [end_event(@rendezvous, false)],
        param1: @idle_ms,
        param2: @idle_ms,
        inverse_phase_mask: CreatureScript.only_in_phases([@waiting])
      ),
      CreatureScript.event(entry, 3, :timer_ooc, [phase(@finale), CreatureScript.timed(finale())],
        param1: @poll_ms,
        param2: @poll_ms,
        param3: @poll_ms,
        param4: @poll_ms,
        inverse_phase_mask: CreatureScript.only_in_phases([@holding_the_line]),
        condition: %Condition{type: :nearby_creature, value1: @elite_guard, value2: @bolvar_reach, reverse?: true}
      )
    ]
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @masquerade => [
        %ScriptStep{
          command: :start_map_event,
          datalong: @masquerade,
          datalong2: @masquerade_s,
          dataint4: @failure_script,
          abort_on_failure?: true,
          failure_condition: %Condition{type: :escort, value1: @source_dead, value2: @max_distance},
          sub_scripts: %{
            @failure_script => [
              %ScriptStep{command: :fail_quest, datalong: @masquerade},
              end_event(@rendezvous, false)
            ]
          }
        },
        phase(@marching),
        npc_flags(@all_flags, @remove_flags),
        talk(@say_on_guard),
        CreatureScript.timed([
          at(5_000, face_angle(@city_gate)),
          at(5_000, talk(@say_justice)),
          at(10_000, by(@marcus, %ScriptStep{command: :mount, datalong: 0})),
          at(10_000, by(@marcus, move(@marcus_post, @walk, 0))),
          at(10_000, prestor_voice()),
          at(10_000, start_route(@procession_route))
          | Enum.map(@bridge_guards, &at(10_000, bridge_guard(&1)))
        ])
      ]
    }
  end

  @impl CreatureScript
  def routes do
    [
      %Route{
        entry: @windsor,
        variant: @procession_route,
        path: path(@procession, %{0 => 87_700, (length(@procession) - 1) => 0}),
        points: procession_points()
      },
      %Route{
        entry: @windsor,
        variant: @keep_route,
        path: path(@keep, %{(length(@keep) - 1) => 0}),
        points: %{0 => salutes(), 1 => salutes(), (length(@keep) - 1) => [here() | throne_room()]}
      }
    ]
  end

  @impl CreatureScript
  def gossip do
    signal? = signal_ready()

    %{
      @rowe => %Gossip{
        texts: [
          %Gossip.Text{text_id: @rowe_nothing},
          %Gossip.Text{text_id: @rowe_ready, condition: signal?},
          %Gossip.Text{text_id: @rowe_busy, condition: and_all([rendezvous_done(), not_masqueraded(), windsor_up()])},
          %Gossip.Text{text_id: @rowe_completed, condition: masqueraded()}
        ],
        options: [%Gossip.Option{text: @signal_option, condition: signal?, steps: send_signal()}]
      },
      @windsor => %Gossip{
        texts: [%Gossip.Text{text_id: @windsor_menu}],
        options: [
          %Gossip.Option{
            text: @ready_option,
            condition:
              and_all([
                %Condition{type: :quest_taken, value1: @masquerade, value2: @incomplete},
                %Condition{type: :map_event_active, value1: @masquerade}
              ]),
            steps: [talk(@say_onward), npc_flags(@all_flags, @remove_flags), start_route(@keep_route)]
          }
        ]
      }
    }
  end

  defp send_signal do
    [
      %ScriptStep{command: :start_map_event, datalong: @rendezvous, datalong2: @rendezvous_s, abort_on_failure?: true},
      npc_flags(@gossip_flag, @remove_flags),
      %ScriptStep{command: :set_run, datalong: 1},
      move(@rowe_road, @run, @signal_road)
    ]
  end

  defp signal_windsor do
    [
      %ScriptStep{command: :emote, datalong: @emote_kneel},
      CreatureScript.timed([
        at(5_000, %ScriptStep{command: :summon_object, datalong: @flare, datalong2: 10, position: @flare_position}),
        at(5_000, move(@rowe_road, @run, 0)),
        at(6_500, summon_windsor()),
        at(6_500, move(@rowe_home, @run, @rowe_home_point))
      ])
    ]
  end

  defp back_at_post do
    [face_angle(@rowe_home), npc_flags(@gossip_flag, @set_flags), talk(@say_signal_sent)]
  end

  defp summon_windsor do
    %ScriptStep{
      command: :summon_creature,
      datalong: @windsor,
      datalong2: @windsor_s * 1_000,
      dataint2: @summon_script,
      dataint3: @no_attack,
      dataint4: @manual_despawn,
      position: @windsor_summon,
      sub_scripts: %{
        @summon_script => [
          %ScriptStep{
            command: :add_map_event_target,
            datalong: @rendezvous,
            dataint4: @cleanup_script,
            sub_scripts: %{@cleanup_script => [%ScriptStep{command: :despawn}]}
          },
          %ScriptStep{command: :mount, datalong: @windsor_mount, datalong2: @is_display_id},
          npc_flags(@questgiver_flag, @remove_flags),
          %ScriptStep{command: :set_run, datalong: 1},
          move(@city_gate, @run, @at_city_gate)
        ]
      }
    }
  end

  defp greet do
    [
      here(),
      CreatureScript.timed([
        at(3_000, %ScriptStep{command: :set_run, datalong: 0}),
        at(3_000, by(@rowe, %ScriptStep{command: :emote, datalong: @emote_salute})),
        at(5_000, %ScriptStep{command: :mount, datalong: 0}),
        at(5_000, cast_self(@dismiss_horse, @triggered)),
        at(5_500, face(@mercutio)),
        at(7_000, talk(@say_dismiss_horse)),
        at(7_000, by(@mercutio, %ScriptStep{command: :set_run, datalong: 1})),
        at(7_000, by(@mercutio, move(@mercutio_pasture, @run, 0))),
        at(12_000, %ScriptStep{command: :turn_to} |> to_player(@rendezvous)),
        at(12_000, npc_flags(@questgiver_flag, @set_flags)),
        at(12_000, talk(@say_greeting) |> to_player(@rendezvous)),
        at(12_000, phase(@waiting))
      ])
    ]
  end

  defp prestor_voice do
    %ScriptStep{
      command: :summon_creature,
      datalong: @prestor,
      datalong2: 10_000,
      dataint2: @summon_script,
      dataint3: @no_attack,
      dataint4: @timed_despawn,
      position: @prestor_voice,
      sub_scripts: %{
        @summon_script => [
          %ScriptStep{command: :morph, datalong: @invisible_model, datalong2: @is_display_id},
          unit_flags(@not_selectable, @set_flags),
          talk(@say_seize_him)
        ]
      }
    }
  end

  defp bridge_guard({post, _kneel}) do
    %ScriptStep{
      command: :summon_creature,
      datalong: @city_guard,
      datalong2: 240_000,
      dataint2: @summon_script,
      dataint3: @no_attack,
      dataint4: @timed_despawn,
      position: post,
      sub_scripts: %{@summon_script => [npc_flags(@gossip_flag, @remove_flags)]}
    }
  end

  defp procession_points do
    last = length(@procession) - 1

    2..last
    |> Map.new(&{&1, salutes()})
    |> Map.put(0, bridge())
    |> Map.update!(2, &[by(@marcus, %ScriptStep{command: :respawn_creature, datalong: 1}) | &1])
    |> Map.update!(last - 1, &(&1 ++ [at(1_000, npc_flags(@gossip_flag, @set_flags)), at(1_000, talk(@say_be_brave))]))
    |> Map.update!(last, &[here() | &1])
  end

  defp bridge do
    marcus_walk_ms = walk_ms(@marcus_post, @marcus_kneel)
    kneel_ms = 67_000 + marcus_walk_ms

    [
      at(1_000, by(@marcus, talk(@say_marcus_cannot))),
      at(6_000, talk(@say_turalyon)),
      at(11_000, talk(@say_not_right)),
      at(16_000, by(@marcus, talk(@say_marcus_lost))),
      at(21_000, by(@marcus, talk(@say_marcus_ashamed))),
      at(26_000, by(@marcus, talk(@say_marcus_shame))),
      at(36_000, talk(@say_vigilant)),
      at(41_000, talk(@say_stand_down)),
      at(46_000, by(@marcus, talk(@say_heroes_walk))),
      at(46_000, kneel_bridge_guards()),
      at(49_000, by(@marcus, talk(@say_move_aside))),
      at(52_000, by(@marcus, %ScriptStep{command: :turn_to})),
      at(52_000, by(@marcus, talk(@say_not_harmed))),
      at(57_000, by(@marcus, %ScriptStep{command: :emote, datalong: @emote_salute})),
      at(62_000, by(@marcus, talk(@say_marcus_go))),
      at(67_000, by(@marcus, move(@marcus_kneel, @walk, 0))),
      at(kneel_ms, by(@marcus, stand(@kneeling))),
      at(kneel_ms, by(@marcus, face_angle(@marcus_kneel))),
      at(kneel_ms, face(@marcus)),
      at(kneel_ms, talk(@say_thank_you)),
      at(kneel_ms + 10_000, face_angle(@city_gate)),
      at(kneel_ms + 10_000, talk(@say_to_the_keep))
    ]
  end

  defp kneel_bridge_guards do
    lines =
      @bridge_guards
      |> Enum.with_index()
      |> Enum.map(fn {{post, kneel}, index} ->
        move_ms = index * 1_000
        kneel_ms = move_ms + 1_000 + walk_ms(post, kneel)

        %{
          CreatureScript.timed([
            at(move_ms, move(kneel, @walk, 0)),
            at(kneel_ms, face_angle(kneel)),
            at(kneel_ms, stand(@kneeling))
          ])
          | condition: at_spot(post)
        }
      end)

    for_all(@city_guard, @bridge_reach, lines)
  end

  defp salutes do
    Enum.map([@city_guard, @patroller, @royal_guard], fn entry ->
      for_all(
        entry,
        @salute_reach,
        [
          %ScriptStep{command: :turn_to},
          %ScriptStep{command: :emote, datalong: @emote_salute}
        ] ++ CreatureScript.pick(Enum.map(@guard_salutes, &[talk(&1)]))
      )
    end)
  end

  defp throne_room do
    [
      at(1_000, talk(@say_run_majesty)),
      at(1_000, by(@bolvar, npc_flags(@gossip_flag + @questgiver_flag, @remove_flags))),
      at(1_000, by(@prestor, npc_flags(@gossip_flag + @questgiver_flag, @remove_flags))),
      at(5_000, by(@bolvar, talk(@say_safe_hall))),
      at(5_000, by(@anduin, %ScriptStep{command: :set_run, datalong: 1})),
      at(5_000, by(@anduin, straight(@safe_hall, @run))),
      at(10_000, face(@prestor)),
      at(10_000, talk(@say_masquerade_over)),
      at(15_000, by(@prestor, talk(@say_prestor_laughs))),
      at(19_000, by(@prestor, talk(@say_incarcerated))),
      at(29_000, by(@prestor, talk(@say_limp_body))),
      at(34_000, talk(@say_prophesied)),
      at(39_000, talk(@say_tablets)),
      at(44_000, talk(@say_not_coding)),
      at(48_000, talk(@say_listen_dragon)),
      at(53_000, talk(@say_reads)),
      at(55_000, %ScriptStep{
        command: :cast_spell,
        datalong: @read_tablets,
        target_type: :nearest_creature_with_entry,
        target_param1: @prestor,
        target_param2: @event_reach
      }),
      at(65_000, by(@prestor, %ScriptStep{command: :update_entry, datalong: @lady_onyxia})),
      at(65_000, by(@lady_onyxia, unit_flags(@not_attackable + @immune_to_npc, @set_flags))),
      at(66_000, by(@bolvar, talk(@say_bolvar_gasps))),
      at(68_000, by(@bolvar, %ScriptStep{command: :set_run, datalong: 1})),
      at(68_000, by(@bolvar, straight(@bolvar_guard_post, @run))),
      at(68_000, by(@lady_onyxia, talk(@say_curious))),
      at(73_900, by(@bolvar, face_angle(@bolvar_guard_post))),
      at(73_900, by(@bolvar, talk(@say_dragon_filth))),
      at(73_900, by(@lady_onyxia, talk(@say_onyxia_laughs))),
      at(75_900, by(@lady_onyxia, talk(@say_come_to_aid))),
      at(75_900, by(@lady_onyxia, unmask_royal_guards())),
      at(79_900, by(@lady_onyxia, %ScriptStep{command: :cast_spell, datalong: @windsor_death})),
      at(81_400, stand(@dead)),
      at(81_400, talk(@say_do_not_let_her_escape)),
      at(82_400, by(@lady_onyxia, talk(@say_was_this_fated))),
      at(82_400, by(@bolvar, bolvar_fights())),
      at(82_400, set_on_bolvar()),
      at(87_400, by(@lady_onyxia, talk(@say_farewell))),
      at(87_400, by(@lady_onyxia, cast_self(@prestor_despawns, @triggered))),
      at(88_400, by(@lady_onyxia, %ScriptStep{command: :despawn, datalong2: @onyxia_respawn_s})),
      at(103_400, by(@bolvar, talk(@say_medallion_shatters))),
      at(103_400, phase(@holding_the_line))
    ]
  end

  defp unmask_royal_guards do
    for_all(@royal_guard, @royal_guard_reach, [
      %ScriptStep{command: :update_entry, datalong: @elite_guard},
      unit_flags(@not_attackable, @set_flags)
      | CreatureScript.pick_weighted([{1, [talk(@say_hiss)]}, {2, []}])
    ])
  end

  defp bolvar_fights do
    %ScriptStep{command: :set_faction, datalong: @bolvar_combat_faction, datalong2: @restore_on_combat_stop}
  end

  defp set_on_bolvar do
    for_all(@elite_guard, @elite_guard_reach, [
      unit_flags(@not_attackable, @remove_flags),
      %ScriptStep{
        command: :attack_start,
        target_type: :nearest_creature_with_entry,
        target_param1: @bolvar,
        target_param2: @bolvar_reach
      }
    ])
  end

  defp finale do
    {bolvar_x, bolvar_y, bolvar_z, _o} = @bolvar_rest

    [
      by(@bolvar, straight({bolvar_x, bolvar_y, bolvar_z, 0.0}, @walk)),
      at(5_000, by(@bolvar, face_angle(@bolvar_rest))),
      at(5_000, by(@bolvar, talk(@say_sorry))),
      at(5_000, by(@bolvar, npc_flags(@questgiver_flag, @set_flags))),
      at(5_000, by(@bolvar, stand(@kneeling))),
      at(6_000, %ScriptStep{
        command: :quest_explored,
        datalong: @masquerade,
        datalong2: @max_distance,
        datalong3: 1,
        target_type: :map_event_target,
        target_param1: @masquerade
      }),
      at(6_000, talk(@say_use_the_medallion)),
      at(14_000, talk(@say_dies)),
      at(14_000, by(@bolvar, CreatureScript.timed(go_home(@bolvar_spawn, @bolvar_rest)))),
      at(14_000, by(@anduin, CreatureScript.timed(go_home(@anduin_spawn, @safe_hall)))),
      at(14_000, end_event(@masquerade, true)),
      at(14_000, end_event(@rendezvous, true)),
      at(14_000, %ScriptStep{command: :despawn, datalong: @corpse_ms}),
      at(14_000, %ScriptStep{command: :deal_damage, datalong: 100, datalong2: 1, target_self?: true})
    ]
  end

  defp go_home({x, y, z, _o} = spawn, from) do
    [
      stand(@standing),
      straight({x, y, z, 0.0}, @walk),
      at(1_000 + walk_ms(from, spawn), face_angle(spawn))
    ]
  end

  defp signal_ready, do: and_all([rendezvous_done(), not_masqueraded(), %{windsor_up() | reverse?: true}])

  defp rendezvous_done,
    do:
      or_any([
        %Condition{type: :quest_taken, value1: @rendezvous, value2: @complete},
        %Condition{type: :quest_rewarded, value1: @rendezvous}
      ])

  defp masqueraded,
    do:
      or_any([
        %Condition{type: :quest_taken, value1: @masquerade, value2: @complete},
        %Condition{type: :quest_rewarded, value1: @masquerade}
      ])

  defp not_masqueraded, do: %Condition{type: :not, children: [masqueraded()]}

  defp windsor_up, do: %Condition{type: :map_event_active, value1: @rendezvous}

  defp and_all(children), do: %Condition{type: :and, children: children}
  defp or_any(children), do: %Condition{type: :or, children: children}

  defp at_spot({x, y, z, _o}),
    do: %Condition{
      type: :distance_to_position,
      value1: x,
      value2: y,
      value3: z,
      value4: @spot_reach,
      swap_targets?: true
    }

  defp path(points, waits) do
    points
    |> Enum.with_index()
    |> Enum.map(fn {{x, y, z}, index} -> {x, y, z, Map.get(waits, index, 1_000)} end)
  end

  defp walk_ms({x1, y1, _z1, _o1}, {x2, y2, _z2, _o2}),
    do: round(:math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2) / @walk_yards_per_s * 1_000)

  defp start_route(variant), do: %ScriptStep{command: :start_waypoints, datalong: @script_route, dataint3: variant}

  defp end_event(event_id, success?),
    do: %ScriptStep{command: :end_map_event, datalong: event_id, datalong2: if(success?, do: 1, else: 0)}

  defp for_all(entry, radius, steps) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @for_all_script,
      datalong2: @creatures,
      datalong3: entry,
      datalong4: radius,
      target_self?: true,
      sub_scripts: %{@for_all_script => steps}
    }
  end

  defp by(entry, %ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @event_reach,
        swap_final?: true
    }
  end

  defp to_player(%ScriptStep{} = step, event_id), do: %{step | target_type: :map_event_target, target_param1: event_id}

  defp face(entry) do
    %ScriptStep{
      command: :turn_to,
      target_type: :nearest_creature_with_entry,
      target_param1: entry,
      target_param2: @event_reach
    }
  end

  defp face_angle({_x, _y, _z, o}), do: %ScriptStep{command: :turn_to, datalong: 1, position: {0.0, 0.0, 0.0, o}}

  defp here, do: %ScriptStep{command: :set_home_position, datalong: 1}

  defp straight(position, pace), do: %ScriptStep{command: :move_to, datalong3: pace, position: position}

  defp move(position, pace, 0), do: %ScriptStep{command: :move_to, datalong3: @pathfind + pace, position: position}

  defp move(position, pace, point),
    do: %ScriptStep{
      command: :move_to,
      datalong3: @pathfind + pace,
      datalong4: @inform,
      dataint: point,
      position: position
    }

  defp npc_flags(mask, mode),
    do: %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: mask, datalong3: mode}

  defp unit_flags(mask, mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: mask, datalong3: mode}

  defp cast_self(spell_id, flags),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}
  defp stand(stand_state), do: %ScriptStep{command: :stand_state, datalong: stand_state}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}
end
