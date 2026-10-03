defmodule ThistleTea.Game.Core.AI.CreatureScript.Onyxia do
  @moduledoc """
  vmangos `boss_onyxia` and `npc_onyxian_whelp`: Onyxia in her lair.

  Onyxia sleeps until she is pulled, then fights on the ground with Flame
  Breath, Cleave, Wing Buffet, Knock Away (which sheds a quarter of her
  victim's threat), and Tail Sweep. At 65 percent health she walks to the
  south end of her chamber, lifts off, and circles above it between eight
  points. Every fifteen to twenty-five seconds she flies on to a neighboring
  point, or takes in a deep breath and sweeps across the chamber to the
  opposite point, setting the egg pits ablaze behind her. While she hangs at
  a point she hurls Fireballs that wipe her target's threat. Whelps pour out
  of the egg chambers: sixteen at first, then a smaller brood thirty seconds
  after each. Below 40 percent, once she hangs at a point, she lands at the
  nearer end of the chamber with a Bellowing Roar that sets off the lava
  fissures, and fights on the ground, roaring again every fifteen to thirty
  seconds over whatever she is casting while single whelps keep hatching.
  Whelps call the whole lair into the fight.

  The circling, the broods, the roars, and the hatching are chains of script
  events Onyxia sends herself. Each handler runs only in the phase that
  started its chain, so landing, an evade, or her death ends them. EventAI
  keeps its phase through an evade, so the evade puts her back on the ground
  in phase 0 and despawns her whelps.

  vmangos also wakes her when a player comes within 58 yards anywhere in the
  lair, evades her when she is dragged out of her chamber, teleports a victim
  she cannot reach to the middle of the chamber, holds her ground abilities
  back while she lands, and respawns her dead Warders when she wakes. This
  port leaves those out.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @onyxia 10_184
  @whelp 11_262

  @say_aggro 8_286
  @say_kill 8_287
  @say_phase_two 8_288
  @say_phase_three 8_290
  @emote_breath 7_213

  @flame_breath 18_435
  @cleave 19_983
  @wing_buffet 18_500
  @knock_away 19_633
  @tail_sweep 15_847
  @bellowing_roar 18_431
  @fireball 18_392
  @heated_ground_east 22_191
  @heated_ground_west 22_197
  @hover 17_131

  @liftoff 254
  @land 293

  @points %{
    0 => {{10.2191, -247.912, -65.896}, 18_617},
    1 => {{-31.4963, -250.123, -65.1278}, 18_576},
    2 => {{-63.5156, -240.096, -65.477}, 18_564},
    3 => {{-65.8444, -213.809, -65.2985}, 18_351},
    4 => {{-58.2509, -189.02, -65.79}, 18_596},
    5 => {{-33.5561, -182.682, -65.9457}, 18_609},
    6 => {{6.8951, -180.246, -65.896}, 18_584},
    7 => {{22.8763, -217.152, -65.0548}, 17_086}
  }
  @first_point 7
  @south_points [2, 3, 4]
  @north_points [0, 1, 5, 6, 7]
  @depart {-57.750641, -215.610077, -85.094727}
  @lift {-57.204933, -215.592148, -85.156929}
  @land_south {-59.895, -214.876, -84.855}
  @land_north {-8.86, -212.752, -88.542}
  @egg_chambers [{-30.127, -254.463, -89.44, 0.0}, {-30.817, -177.106, -89.258, 0.0}]
  @breath_speed 21.0

  @ground 0
  @taking_off 1
  @flying 2
  @landing 4
  @landed 5
  @hovering 10

  @point_motion 9
  @depart_point 20
  @landing_point 21

  @move_on 1
  @brood 2
  @roar 3
  @hatch 4
  @first_brood 1
  @later_brood 0

  @interrupt_previous 0x01
  @triggered 0x02
  @pathfind 0x01
  @run 0x04
  @fly 0x08
  @point_movement 0x02
  @summon_run 0x01
  @hostile_random 4
  @timed_or_corpse 2
  @victim_target 1
  @all_attackers 8
  @creatures 2
  @lair_radius 200
  @despawn_script 1

  @impl CreatureScript
  def entries, do: [@onyxia, @whelp]

  @impl CreatureScript
  def events(@onyxia) do
    [
      event(1, :aggro, [talk(@say_aggro), zone_pulse()]),
      event(2, :kill, [talk(@say_kill)], chance: 50),
      event(3, :evade, [
        %ScriptStep{command: :set_phase, datalong: @ground},
        set_fly(false),
        remove_aura(@hover),
        set_combat_movement(true),
        set_melee_attack(true),
        despawn_whelps()
      ])
    ] ++ ground_abilities() ++ takeoff() ++ circling() ++ broods() ++ landing() ++ phase_three()
  end

  def events(@whelp), do: [CreatureScript.event(@whelp, 1, :aggro, [zone_pulse()])]

  defp ground_abilities do
    [
      on_ground(10, :timer_in_combat, [cast_victim(@flame_breath)], timer(10_000, 20_000, 10_000, 20_000)),
      on_ground(11, :timer_in_combat, [cast_victim(@cleave)], timer(2_000, 5_000, 2_000, 5_000)),
      on_ground(12, :timer_in_combat, [cast_victim(@wing_buffet)], timer(10_000, 20_000, 15_000, 30_000)),
      on_ground(
        13,
        :timer_in_combat,
        [cast_victim(@knock_away), shed_threat(@victim_target, -25)],
        timer(15_000, 25_000, 15_000, 30_000)
      ),
      on_ground(14, :timer_in_combat, [cast_self(@tail_sweep)], timer(5_000, 5_000, 3_500, 3_500))
    ]
  end

  defp takeoff do
    [
      event(
        20,
        :hp,
        [
          talk(@say_phase_two),
          %ScriptStep{command: :interrupt_casts},
          set_combat_movement(false),
          set_melee_attack(false),
          %ScriptStep{command: :set_phase, datalong: @taking_off},
          move_to(@depart, @pathfind + @run, @depart_point)
        ],
        param1: 65,
        repeatable?: false,
        inverse_phase_mask: CreatureScript.only_in_phases([@ground])
      ),
      event(
        21,
        :movement_inform,
        [
          emote(@liftoff),
          set_fly(true),
          CreatureScript.timed([
            at(1_000, move_to(@lift, @run + @fly, nil)),
            at(3_000, cast_self(@hover, @triggered)),
            at(3_000, %ScriptStep{command: :set_phase, datalong: @flying}),
            at(3_000, fly_to(@first_point)),
            at(8_000, send_self(@brood, @first_brood))
          ])
        ],
        param1: @point_motion,
        param2: @depart_point,
        inverse_phase_mask: CreatureScript.only_in_phases([@taking_off])
      )
    ]
  end

  defp circling do
    arrivals =
      for point <- 0..7 do
        event(
          30 + point,
          :movement_inform,
          [%ScriptStep{command: :set_phase, datalong: @hovering + point} | linger(point)],
          param1: @point_motion,
          param2: point,
          inverse_phase_mask: CreatureScript.only_in_phases([@flying])
        )
      end

    departures =
      for point <- 0..7 do
        event(
          40 + point,
          :script_event,
          CreatureScript.pick_weighted([
            {35, fly_on(rem(point + 1, 8))},
            {35, fly_on(rem(point + 7, 8))},
            {30, deep_breath(point)}
          ]),
          param1: @move_on,
          param2: point,
          inverse_phase_mask: CreatureScript.only_in_phases([@hovering + point])
        )
      end

    fireball =
      event(
        50,
        :timer_in_combat,
        [cast_victim(@fireball), shed_threat(@victim_target, -100)],
        timer(3_000, 3_000, 3_000, 3_000) ++ [inverse_phase_mask: hovering_phases()]
      )

    arrivals ++ departures ++ [fireball]
  end

  defp linger(point) do
    CreatureScript.pick(for delay <- [15_000, 17_500, 20_000, 22_500, 25_000], do: send_later(delay, @move_on, point))
  end

  defp fly_on(point) do
    [%ScriptStep{command: :interrupt_casts}, %ScriptStep{command: :set_phase, datalong: @flying}, fly_to(point)]
  end

  defp deep_breath(point) do
    {{x, y, _z}, breath} = Map.fetch!(@points, point)
    across = rem(point + 4, 8)
    {{to_x, to_y, _to_z}, _breath} = Map.fetch!(@points, across)
    crossing_ms = round(:math.sqrt((to_x - x) ** 2 + (to_y - y) ** 2) / @breath_speed * 1_000)

    [
      %ScriptStep{command: :interrupt_casts},
      %ScriptStep{command: :set_phase, datalong: @flying},
      talk(@emote_breath),
      cast_self(breath),
      CreatureScript.timed([
        at(5_000, %{fly_to(across) | datalong2: crossing_ms}),
        at(5_000, cast_self(@heated_ground_east, @triggered)),
        at(5_000, cast_self(@heated_ground_west, @triggered))
      ])
    ]
  end

  defp broods do
    airborne = CreatureScript.only_in_phases([@flying | Enum.map(0..7, &(@hovering + &1))])

    [
      event(60, :script_event, [brood(8)],
        param1: @brood,
        param2: @first_brood,
        inverse_phase_mask: airborne
      ),
      event(61, :script_event, CreatureScript.pick_weighted([{2, [brood(3)]}, {1, [brood(4)]}]),
        param1: @brood,
        param2: @later_brood,
        inverse_phase_mask: airborne
      )
    ]
  end

  defp brood(pairs) do
    whelps =
      for pair <- 0..(pairs - 1), chamber <- @egg_chambers do
        at(pair * 1_000, whelp(chamber, 300_000))
      end

    CreatureScript.timed(whelps ++ [at(pairs * 1_000 + 30_000, send_self(@brood, @later_brood))])
  end

  defp landing do
    land = fn index, points, spot ->
      event(
        index,
        :hp,
        [
          %ScriptStep{command: :interrupt_casts},
          shed_threat(@all_attackers, -100),
          talk(@say_phase_three),
          %ScriptStep{command: :set_phase, datalong: @landing},
          remove_aura(@hover),
          move_to(spot, @run + @fly, @landing_point)
        ],
        param1: 40,
        repeatable?: false,
        inverse_phase_mask: CreatureScript.only_in_phases(Enum.map(points, &(@hovering + &1)))
      )
    end

    [
      land.(70, @south_points, @land_south),
      land.(71, @north_points, @land_north),
      event(
        72,
        :movement_inform,
        [
          set_fly(false),
          emote(@land),
          cast_self(@bellowing_roar, @triggered),
          CreatureScript.timed([
            at(2_000, set_combat_movement(true)),
            at(2_000, set_melee_attack(true)),
            at(2_000, %ScriptStep{command: :set_phase, datalong: @landed}),
            at(2_000, %ScriptStep{command: :attack_start, target_type: :victim})
          ])
        ] ++ roar_later() ++ hatch_later(),
        param1: @point_motion,
        param2: @landing_point,
        inverse_phase_mask: CreatureScript.only_in_phases([@landing])
      )
    ]
  end

  defp phase_three do
    landed = CreatureScript.only_in_phases([@landed])

    [
      event(80, :script_event, [cast_self(@bellowing_roar, @interrupt_previous) | roar_later()],
        param1: @roar,
        inverse_phase_mask: landed
      ),
      event(81, :script_event, CreatureScript.pick(Enum.map(@egg_chambers, &[whelp(&1, 120_000)])) ++ hatch_later(),
        param1: @hatch,
        inverse_phase_mask: landed
      )
    ]
  end

  defp roar_later,
    do: CreatureScript.pick(for delay <- [15_000, 20_000, 25_000, 30_000], do: send_later(delay, @roar, 0))

  defp hatch_later,
    do: CreatureScript.pick(for delay <- [1_000, 4_000, 7_000, 10_000], do: send_later(delay, @hatch, 0))

  defp send_later(delay, event_id, data), do: [CreatureScript.timed([at(delay, send_self(event_id, data))])]

  defp send_self(event_id, data),
    do: %ScriptStep{command: :send_script_event, datalong: event_id, datalong2: data, target_self?: true}

  defp whelp(position, lifetime_ms) do
    %ScriptStep{
      command: :summon_creature,
      datalong: @whelp,
      datalong2: lifetime_ms,
      dataint: @summon_run,
      dataint3: @hostile_random,
      dataint4: @timed_or_corpse,
      position: position
    }
  end

  defp despawn_whelps do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @despawn_script,
      datalong2: @creatures,
      datalong3: @whelp,
      datalong4: @lair_radius,
      sub_scripts: %{@despawn_script => [%ScriptStep{command: :despawn}]}
    }
  end

  defp fly_to(point) do
    {position, _breath} = Map.fetch!(@points, point)
    move_to(position, @pathfind + @run + @fly, point)
  end

  defp move_to({x, y, z}, options, point) do
    %ScriptStep{
      command: :move_to,
      datalong3: options,
      datalong4: if(point, do: @point_movement, else: 0),
      dataint: point || 0,
      position: {x, y, z, 0.0}
    }
  end

  defp hovering_phases, do: CreatureScript.only_in_phases(Enum.map(0..7, &(@hovering + &1)))

  defp on_ground(index, event_type, steps, opts),
    do: event(index, event_type, steps, [inverse_phase_mask: CreatureScript.only_in_phases([@ground, @landed])] ++ opts)

  defp event(index, event_type, steps, opts \\ []), do: CreatureScript.event(@onyxia, index, event_type, steps, opts)

  defp timer(initial_min, initial_max, repeat_min, repeat_max),
    do: [param1: initial_min, param2: initial_max, param3: repeat_min, param4: repeat_max]

  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}

  defp shed_threat(target, percent),
    do: %ScriptStep{command: :modify_threat, datalong: target, position: {percent, 0.0, 0.0, 0.0}}

  defp set_fly(enabled?), do: %ScriptStep{command: :set_fly, datalong: flag(enabled?)}
  defp set_combat_movement(enabled?), do: %ScriptStep{command: :set_combat_movement, datalong: flag(enabled?)}
  defp set_melee_attack(enabled?), do: %ScriptStep{command: :set_melee_attack, datalong: flag(enabled?)}
  defp flag(enabled?), do: if(enabled?, do: 1, else: 0)

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp remove_aura(spell_id), do: %ScriptStep{command: :remove_aura, datalong: spell_id}
  defp emote(emote_id), do: %ScriptStep{command: :emote, datalong: emote_id}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp zone_pulse, do: %ScriptStep{command: :zone_combat_pulse}
end
