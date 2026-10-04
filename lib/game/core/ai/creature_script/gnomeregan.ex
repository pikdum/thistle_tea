defmodule ThistleTea.Game.Core.AI.CreatureScript.Gnomeregan do
  @moduledoc """
  vmangos `npc_blastmaster_emi_shortfuse` and `boss_thermaplugg`, the
  Grubbis event and the last fight of Gnomeregan
  (`InstanceScript.Gnomeregan`).

  Blastmaster Emi Shortfuse offers to begin while Grubbis still lives. She
  walks the party down to the two cave-ins and opens the southern one, where
  Caverndeep troggs pour in pack after pack while she plants two explosive
  charges. She will not fight while she sets a charge. Once the second is set
  she counts down, blows the tunnel shut, and does the same at the northern
  cave-in. At the end Grubbis and Chomper come up from below. When Grubbis
  dies she blows the northern tunnel and celebrates with a firework. Every
  creature the event summons vanishes if she dies.

  Mekgineer Thermaplugg knocks his target away, and from half health knocks
  away everyone around him. He keeps activating bombs, each opening a random
  gnome face, faster in the second half of the fight.

  Like the disciple of Naralex, Emi holds at each scene's point until it plays
  out and fights back on the way. Her scenes keep time while she fights, where
  vmangos stops their clock until the fight is over, and she does not turn to
  the player who started the event before her first countdown.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @emi 7_998
  @grubbis 7_361
  @chomper 6_215
  @burrower 6_206
  @ambusher 6_207
  @thermaplugg 7_800

  @grubbis_field 0
  @charge_field 2
  @south_cave_in_field 3
  @north_cave_in_field 4
  @face_fields 10..15
  @not_started 0
  @in_progress 1
  @failed 2
  @detonate 5

  @say_start 4_050
  @say_intro_1 4_051
  @say_intro_2 4_052
  @say_intro_3 4_129
  @say_intro_4 4_130
  @say_look_1 4_131
  @say_hear_1 4_132
  @say_aggro_1 5_161
  @say_aggro_2 5_164
  @say_charge_1 4_133
  @say_charge_2 4_134
  @say_blow_1_10 4_135
  @say_blow_1_5 4_136
  @say_blow 4_137
  @say_finish_1 4_206
  @say_look_2 4_207
  @say_hear_2 4_208
  @say_charge_3 4_209
  @say_charge_4 4_325
  @say_blow_2_10 4_326
  @say_blow_2_5 4_327
  @say_blow_soon 4_329
  @say_finish_2 4_446
  @say_grubbis_spawn 4_328
  @begin_option "I am ready to begin."

  @say_thermaplugg_aggro 6_173
  @say_thermaplugg_phase 6_174
  @say_thermaplugg_slay 6_175
  @say_thermaplugg_bomb 6_176

  @explosion_north 12_158
  @explosion_south 12_159
  @red_fireworks 11_542
  @knock_away 10_101
  @knock_away_all 11_130
  @activate_bomb_a 11_511
  @activate_bomb_b 11_795

  @path [
    {-510.13, -132.69, -152.5},
    {-511.099, -129.74, -153.845},
    {-511.79, -127.476, -155.551},
    {-512.969, -124.926, -156.115},
    {-513.972, -120.236, -156.116},
    {-514.388, -115.19, -156.117},
    {-514.304, -111.478, -155.52},
    {-514.84, -107.663, -154.893},
    {-518.994, -101.416, -154.648},
    {-526.998, -98.1488, -155.625},
    {-534.569, -105.41, -155.989},
    {-535.534, -104.695, -155.971},
    {-541.63, -98.6583, -155.858},
    {-535.092, -99.9175, -155.974},
    {-519.01, -101.51, -154.677},
    {-504.466, -97.848, -150.955},
    {-506.907, -89.1474, -151.083},
    {-512.758, -101.902, -153.198},
    {-519.988, -124.848, -156.128}
  ]

  @intro_point 3
  @cave_in_view 8
  @first_charge 10
  @second_charge 12
  @south_blast 14
  @third_charge 15
  @fourth_charge 16
  @last_stand 18
  @intro_wait_ms 5_000

  @south_cave_in {-541.607, -105.434}
  @north_cave_in {-505.096, -93.973}

  @packs %{
    1 => [
      {@ambusher, {-566.8114, -111.7036, -151.1891, 5.986479}},
      {@ambusher, {-568.5875, -113.7559, -151.1869, 0.06981317}},
      {@ambusher, {-570.2333, -116.8126, -151.2272, 0.296706}},
      {@ambusher, {-550.6331, -108.7592, -153.965, 0.8901179}},
      {@ambusher, {-558.9717, -115.0669, -151.8799, 0.5235988}},
      {@ambusher, {-556.6719, -112.0526, -152.8255, 0.4886922}},
      {@ambusher, {-552.6419, -113.4385, -153.0727, 0.8028514}},
      {@ambusher, {-549.1248, -112.1469, -153.7987, 0.7504916}},
      {@ambusher, {-546.7435, -112.3051, -154.2225, 0.9250245}}
    ],
    2 => [
      {@ambusher, {-571.4071, -108.7721, -150.6547, 5.480334}},
      {@ambusher, {-573.797, -106.5265, -150.4106, 5.550147}},
      {@ambusher, {-576.3784, -108.0483, -150.4227, 5.585053}},
      {@ambusher, {-576.697, -111.7413, -150.6484, 5.759586}}
    ],
    3 => [
      {@ambusher, {-571.3161, -114.4412, -151.0931, 6.021386}},
      {@ambusher, {-570.3127, -111.7964, -151.04, 2.042035}}
    ],
    4 => [
      {@ambusher, {-474.5954, -104.074, -146.0483, 2.338741}},
      {@ambusher, {-477.9396, -108.6563, -145.7394, 1.553343}},
      {@ambusher, {-475.6625, -97.12168, -146.5959, 1.291544}},
      {@ambusher, {-480.5233, -88.40702, -146.3772, 3.001966}}
    ],
    5 => [
      {@ambusher, {-474.2943, -105.2212, -145.9747, 2.251475}},
      {@ambusher, {-481.1831, -101.4225, -146.377, 2.146755}},
      {@burrower, {-475.0871, -100.016, -146.4382, 2.303835}},
      {@ambusher, {-478.8562, -106.9321, -145.8533, 1.658063}}
    ],
    6 => [
      {@ambusher, {-473.8762, -107.4022, -145.838, 2.024582}},
      {@ambusher, {-490.5134, -92.72843, -148.0954, 3.054326}},
      {@ambusher, {-491.401, -88.25341, -148.0358, 3.560472}},
      {@ambusher, {-479.1431, -106.227, -145.9097, 1.727876}},
      {@ambusher, {-475.3185, -101.4804, -146.2717, 2.234021}},
      {@ambusher, {-485.1559, -89.57419, -146.9299, 3.071779}},
      {@ambusher, {-482.2516, -96.80614, -146.6596, 2.303835}},
      {@ambusher, {-477.9874, -92.82047, -146.6944, 3.124139}}
    ],
    7 => [
      {@grubbis, {-476.3761, -108.1901, -145.7763, 1.919862}},
      {@chomper, {-473.1326, -103.0901, -146.1155, 2.042035}}
    ]
  }

  @northern_packs [4, 5, 6]
  @cave_in_scatter 2.0

  @escorting 1
  @awaiting_grubbis 2
  @finale 3
  @second_half 1

  @hold_ms 1_800_000
  @event_s 3_600
  @event_reach 100
  @summon_lifetime_ms 3_600_000

  @escort_faction 113
  @npc_flags_field 147
  @all_flags 0xFFFF_FFFF
  @remove_flags 2
  @use_standing 69
  @no_emote 0
  @cheer 4
  @point 25
  @passive 0
  @aggressive 2
  @no_attack -1
  @dead_despawn 7
  @script_route 5
  @summon_script 1
  @cleanup_script 1
  @pathfind 0x1

  def emi, do: @emi

  @impl CreatureScript
  def entries, do: [@emi, @thermaplugg]

  @impl CreatureScript
  def events(@emi = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [%{talk(@say_aggro_1) | dataint2: @say_aggro_2}], chance: 33),
      CreatureScript.event(entry, 2, :death, [end_event(false)]),
      CreatureScript.event(entry, 3, :summoned_just_died, finale(),
        param1: @grubbis,
        inverse_phase_mask: CreatureScript.only_in_phases([@awaiting_grubbis])
      )
    ]
  end

  def events(@thermaplugg = entry) do
    first_half = CreatureScript.only_in_phases([0])
    second_half = CreatureScript.only_in_phases([@second_half])

    [
      CreatureScript.event(entry, 1, :aggro, [talk(@say_thermaplugg_aggro)]),
      CreatureScript.event(entry, 2, :kill, [talk(@say_thermaplugg_slay)]),
      CreatureScript.event(entry, 3, :hp, [talk(@say_thermaplugg_phase), phase(@second_half)],
        param1: 50,
        param2: 0,
        repeatable?: false,
        inverse_phase_mask: first_half
      ),
      CreatureScript.event(entry, 4, :timer_in_combat, [cast(@knock_away, :victim)],
        param1: 17_000,
        param2: 20_000,
        param3: 17_000,
        param4: 20_000,
        inverse_phase_mask: first_half
      ),
      CreatureScript.event(entry, 5, :timer_in_combat, [cast_self(@knock_away_all)],
        param1: 12_000,
        param2: 12_000,
        param3: 12_000,
        param4: 12_000,
        inverse_phase_mask: second_half
      ),
      CreatureScript.event(entry, 6, :timer_in_combat, activate_bomb(@activate_bomb_a),
        param1: 10_000,
        param2: 15_000,
        param3: 12_000,
        param4: 17_000,
        inverse_phase_mask: first_half
      ),
      CreatureScript.event(entry, 7, :timer_in_combat, activate_bomb(@activate_bomb_b),
        param1: 6_000,
        param2: 12_000,
        param3: 6_000,
        param4: 12_000,
        inverse_phase_mask: second_half
      ),
      CreatureScript.event(entry, 8, :evade, [phase(0)])
    ]
  end

  @impl CreatureScript
  def gossip do
    ready = %Condition{
      type: :or,
      children: [
        %Condition{type: :instance_data, value1: @grubbis_field, value2: @not_started},
        %Condition{type: :instance_data, value1: @grubbis_field, value2: @failed}
      ]
    }

    %{@emi => %Gossip{options: [%Gossip.Option{text: @begin_option, condition: ready, steps: begin()}]}}
  end

  @impl CreatureScript
  def routes do
    [%Route{entry: @emi, path: path(), points: points()}]
  end

  defp begin do
    [
      %ScriptStep{command: :start_map_event, datalong: @emi, datalong2: @event_s},
      instance_data(@grubbis_field, @in_progress),
      CreatureScript.timed([
        at(1_000, talk(@say_start)),
        at(1_000, CreatureScript.faction(@escort_faction)),
        at(1_000, %ScriptStep{
          command: :modify_flags,
          datalong: @npc_flags_field,
          datalong2: @all_flags,
          datalong3: @remove_flags
        }),
        at(6_000, talk(@say_intro_1)),
        at(9_500, %ScriptStep{command: :set_run, datalong: 0}),
        at(9_500, phase(@escorting)),
        at(9_500, resume(0))
      ])
    ]
  end

  defp path do
    waits =
      Map.new(
        [@cave_in_view, @first_charge, @second_charge, @south_blast, @third_charge, @fourth_charge, @last_stand],
        &{&1, @hold_ms}
      )

    waits = Map.put(waits, @intro_point, @intro_wait_ms)

    @path
    |> Enum.with_index()
    |> Enum.map(fn {{x, y, z}, index} -> {x, y, z, Map.get(waits, index, 0)} end)
  end

  defp points do
    %{
      @intro_point => [CreatureScript.timed([at(1_000, talk(@say_intro_2))])],
      @cave_in_view => cave_in_view(),
      @first_charge => plant_charge(@first_charge, 2, 1, 15_000, 30_000, [at(30_000, talk(@say_charge_1))]),
      @second_charge => plant_charge(@second_charge, 3, 2, 10_000, 25_000, [at(21_000, talk(@say_charge_2))]),
      @south_blast => south_blast(),
      @third_charge => plant_charge(@third_charge, 5, 3, 15_000, 30_000, []),
      @fourth_charge => plant_charge(@fourth_charge, 6, 4, 10_000, 23_000, [at(20_000, talk(@say_charge_4))]),
      @last_stand => last_stand()
    }
  end

  defp cave_in_view do
    [
      CreatureScript.timed(
        [
          at(2_000, talk(@say_intro_3)),
          at(8_000, talk(@say_intro_4)),
          at(17_000, face_toward(@cave_in_view, @south_cave_in)),
          at(19_000, talk(@say_look_1)),
          at(24_000, talk(@say_hear_1))
        ] ++
          Enum.map(pack(1), &at(26_000, &1)) ++
          [at(27_000, instance_data(@south_cave_in_field, 1)), at(27_000, resume(@cave_in_view + 1))]
      )
    ]
  end

  defp plant_charge(point, pack, charge, planted_ms, leave_ms, lines) do
    [
      react(@passive),
      emote(@use_standing),
      CreatureScript.timed(
        Enum.map(pack(pack), &at(planted_ms, &1)) ++
          [
            at(planted_ms, instance_data(@charge_field, charge)),
            at(planted_ms, emote(@no_emote)),
            at(planted_ms, react(@aggressive))
          ] ++ lines ++ [at(leave_ms, resume(point + 1))]
      )
    ]
  end

  defp south_blast do
    [
      face_toward(@south_blast, @south_cave_in),
      talk(@say_blow_1_10),
      CreatureScript.timed(
        [
          at(5_000, talk(@say_blow_1_5)),
          at(10_000, talk(@say_blow)),
          at(11_000, cast_self(@explosion_south)),
          at(11_500, instance_data(@south_cave_in_field, 0)),
          at(11_500, instance_data(@charge_field, @detonate)),
          at(16_500, emote(@cheer)),
          at(22_500, talk(@say_finish_1)),
          at(28_500, talk(@say_look_2)),
          at(31_500, face_toward(@south_blast, @north_cave_in)),
          at(34_500, talk(@say_hear_2))
        ] ++
          Enum.map(pack(4), &at(42_500, &1)) ++
          [
            at(42_500, talk(@say_charge_3)),
            at(42_500, instance_data(@north_cave_in_field, 1)),
            at(42_500, resume(@south_blast + 1))
          ]
      )
    ]
  end

  defp last_stand do
    [
      CreatureScript.timed(
        [
          at(2_000, face_toward(@last_stand, @north_cave_in)),
          at(2_000, talk(@say_blow_2_10)),
          at(7_000, talk(@say_blow_2_5)),
          at(8_000, phase(@awaiting_grubbis))
        ] ++
          Enum.map(pack(7), &at(8_000, &1)) ++
          [at(9_000, by(@grubbis, talk(@say_grubbis_spawn)))]
      )
    ]
  end

  defp finale do
    [
      phase(@finale),
      CreatureScript.timed([
        at(1_000, face_toward(@last_stand, @north_cave_in)),
        at(1_000, emote(@cheer)),
        at(6_000, talk(@say_blow_soon)),
        at(11_000, talk(@say_blow)),
        at(13_000, emote(@point)),
        at(14_000, cast_self(@explosion_north)),
        at(14_500, instance_data(@north_cave_in_field, 0)),
        at(14_500, instance_data(@charge_field, @detonate)),
        at(22_500, cast_self(@red_fireworks)),
        at(22_500, talk(@say_finish_2)),
        at(22_500, end_event(true))
      ])
    ]
  end

  defp activate_bomb(spell_id) do
    faces = for field <- @face_fields, do: [instance_data(field, 1)]

    [cast_self(spell_id)] ++
      CreatureScript.pick(faces) ++ CreatureScript.pick_weighted([{1, [talk(@say_thermaplugg_bomb)]}, {5, []}])
  end

  defp pack(number) do
    door = if number in @northern_packs, do: @north_cave_in, else: @south_cave_in
    Enum.map(Map.fetch!(@packs, number), fn {entry, position} -> summon(entry, position, door) end)
  end

  defp summon(entry, position, door) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @summon_lifetime_ms,
      dataint2: @summon_script,
      dataint3: @no_attack,
      dataint4: @dead_despawn,
      position: position,
      sub_scripts: %{@summon_script => [map_event_target() | approach(entry, door)]}
    }
  end

  defp approach(entry, _door) when entry in [@grubbis, @chomper], do: []

  defp approach(_entry, {x, y}) do
    [
      %ScriptStep{
        command: :move_to,
        datalong: 3,
        datalong3: @pathfind,
        position: {x, y, door_z({x, y}), @cave_in_scatter}
      }
    ]
  end

  defp door_z(@south_cave_in), do: -151.829
  defp door_z(@north_cave_in), do: -147.814

  defp map_event_target do
    %ScriptStep{
      command: :add_map_event_target,
      datalong: @emi,
      dataint4: @cleanup_script,
      sub_scripts: %{@cleanup_script => [%ScriptStep{command: :despawn, condition: %Condition{type: :alive}}]}
    }
  end

  defp face_toward(point, {tx, ty}) do
    {x, y, _z} = Enum.at(@path, point)
    angle = :math.atan2(ty - y, tx - x)
    angle = if angle < 0, do: angle + 2 * :math.pi(), else: angle
    %ScriptStep{command: :turn_to, datalong: 1, position: {0.0, 0.0, 0.0, angle}}
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

  defp resume(point), do: %ScriptStep{command: :start_waypoints, datalong: @script_route, datalong2: point}

  defp end_event(success?),
    do: %ScriptStep{command: :end_map_event, datalong: @emi, datalong2: if(success?, do: 1, else: 0)}

  defp cast(spell_id, target_type), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: target_type}
  defp cast_self(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_self?: true}
  defp instance_data(field, value), do: %ScriptStep{command: :set_instance_data, datalong: field, datalong2: value}
  defp react(state), do: %ScriptStep{command: :set_react_state, datalong: state}
  defp emote(emote_id), do: %ScriptStep{command: :emote, datalong: emote_id}
  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}
end
