defmodule ThistleTea.Game.Core.AI.CreatureScript.ErisHavenfire do
  @moduledoc """
  vmangos `npc_eris_havenfire` and `npc_eris_havenfire_peasant`, The Balance
  of Light and Shadow (7622), the priest's Benediction trial in the Eastern
  Plaguelands.

  Accepting the quest starts a map event keyed by the quest. Eight Scourge
  Archers take the ridges, a Peasant Light Trap marks the sanctuary, and five
  waves of fleeing peasants, 12, 12, 12, 13, and 16 strong, run from the
  burning village every 80 seconds from the tenth. One to four of each wave
  are plagued, carrying a Seething Plague that kills in twenty seconds unless
  cured. The peasants walk to the road and on to the light, never fighting
  back, while the archers loose at a random one every three to four and a half
  seconds; an archer's arrow hits as hard as vmangos makes it, and one in
  eleven brings Death's Door. From the hundredth second Eris blesses everyone
  near her every 75 to 90 seconds, and Scourge Footsoldiers rush in every ten
  to fourteen, most of them for the priest. Each peasant who reaches the
  light counts as saved; each who falls is hung on the death post in turn.
  Fifty saved complete the quest. A fifteenth death, the priest straying from
  the field, or the event running past its time fails it, and Eris leaves to
  return five minutes later; the event's creatures and the light go with
  either ending. The light raises the death posts, so they outlast the corpses
  and come down with it. vmangos also calls The Cleaner on anyone else who
  helps; that interference rule is not ported.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @eris 14_494
  @injured 14_484
  @plagued 14_485
  @footsoldier 14_486
  @archer 14_489
  @peasants [@injured, @plagued]
  @light 179_693
  @quest 7_622

  @seething_plague 23_072
  @shoot 23_073
  @blessing_of_nordrassil 23_108
  @deaths_door 23_127

  @saved 0
  @died 1
  @saves_needed 50
  @deaths_allowed 14
  @time_limit_s 900
  @sight_distance 150
  @respawn_after_failure_s 300
  @death_post_s 1_200
  @archer_reach 60
  @light_reach 60
  @field_reach 100
  @arrow_bonus_damage 57

  @success_script 1
  @failure_script 2
  @despawn_script 3
  @cry_script 4
  @triggered 0x02
  @pathfind_walk 0x3
  @random_point 3
  @inform 0x2
  @point_motion 9
  @to_road 1
  @to_light 2
  @passive 0
  @ranged_sheath 2
  @no_attack -1
  @attack_event_target 23
  @dead_despawn 7

  @peasant_spawn {3_358.11, -3_049.81, 166.23, 1.87}
  @spawn_scatter 6.0
  @road {3_353.80, -3_042.16, 163.68, 6.0}
  @sanctuary {3_327.0, -2_970.0, 161.0, 3.0}
  @light_position {3_327.0, -2_970.0, 160.034, 5.2135}
  @footsoldier_scatter 5.0

  @wave_sizes [12, 12, 12, 13, 16]
  @first_wave_ms 10_000
  @wave_interval_ms 80_000
  @assault_ms 100_000

  @footsoldier_spots [
    {3_366.0, -3_045.0, 166.0, 3.3},
    {3_345.0, -3_054.0, 167.0, 0.4},
    {3_364.0, -3_057.0, 166.0, 2.0}
  ]

  @archer_posts [
    {3_327.076, -3_017.9831, 171.5497, 5.777},
    {3_313.686, -3_038.0459, 168.5863, 0.072},
    {3_333.0, -3_052.0, 175.0, 0.61},
    {3_380.0, -3_040.0, 174.0, 3.3885},
    {3_381.0, -3_060.0, 184.0, 2.5991},
    {3_371.4809, -3_070.0302, 175.166, 1.952},
    {3_347.1079, -3_071.3110, 177.910, 1.356},
    {3_358.7299, -3_075.9846, 174.794, 1.575}
  ]

  @death_posts [
    {179_694, {3_355.48, -3_010.68, 175.212, 5.06146}},
    {179_698, {3_352.82, -3_007.79, 177.409, 2.53072}},
    {179_695, {3_353.07, -3_009.16, 176.615, 3.01941}},
    {179_699, {3_354.08, -3_010.35, 172.769, 2.46091}},
    {179_696, {3_353.87, -3_007.88, 171.79, 5.18363}},
    {179_696, {3_353.28, -3_013.75, 173.584, 1.20428}},
    {179_696, {3_353.34, -3_009.84, 173.532, 1.98967}},
    {179_698, {3_353.8, -3_009.6, 175.499, 0.802851}},
    {179_699, {3_355.88, -3_014.61, 173.609, 5.58505}},
    {179_699, {3_354.33, -3_012.57, 173.045, 5.06146}},
    {179_696, {3_354.29, -3_011.48, 171.916, 2.80997}},
    {179_695, {3_354.74, -3_013.16, 176.816, 2.61799}},
    {179_698, {3_355.1, -3_013.5, 176.482, 0.139625}},
    {179_699, {3_351.66, -3_007.61, 175.0, 4.53786}}
  ]

  @wave_cries [9_712, 9_713, 9_714, 9_715]
  @farewells [9_654, 9_652, 9_650, 9_653]
  @laments [9_682, 9_680, 9_683]
  @eris_failed [9_648, 9_649]
  @eris_saved 9_728
  @eris_heals 9_655

  @event_running %Condition{type: :map_event_active, value1: @quest}

  @impl CreatureScript
  def entries, do: [@eris, @injured, @plagued, @archer, @footsoldier]

  @impl CreatureScript
  def events(@eris), do: eris_events()
  def events(entry) when entry in @peasants, do: peasant_events(entry)
  def events(@archer), do: archer_events()
  def events(@footsoldier), do: [CreatureScript.event(@footsoldier, 1, :spawned, [join_event()])]

  @impl CreatureScript
  def quest_start_steps do
    %{
      @quest =>
        [
          start_event(),
          %ScriptStep{command: :summon_object, datalong: @light, datalong2: @time_limit_s, position: @light_position}
        ] ++ Enum.map(@archer_posts, &summon(@archer, &1)) ++ [CreatureScript.timed(timeline())]
    }
  end

  defp start_event do
    %ScriptStep{
      command: :start_map_event,
      datalong: @quest,
      datalong2: @time_limit_s,
      dataint2: @success_script,
      dataint4: @failure_script,
      abort_on_failure?: true,
      success_condition: tally(@saved, @saves_needed),
      failure_condition: %Condition{
        type: :or,
        children: [tally(@died, @deaths_allowed + 1), %Condition{type: :escort, value2: @sight_distance}]
      },
      sub_scripts: %{
        @success_script => [
          %ScriptStep{command: :quest_explored, datalong: @quest, datalong2: @sight_distance},
          talk([@eris_saved]),
          put_out_light(),
          phase(0)
        ],
        @failure_script => [
          %ScriptStep{command: :fail_quest, datalong: @quest},
          talk(@eris_failed),
          put_out_light(),
          phase(0),
          %ScriptStep{command: :despawn, datalong2: @respawn_after_failure_s}
        ]
      }
    }
  end

  defp timeline do
    waves =
      @wave_sizes
      |> Enum.with_index()
      |> Enum.map(fn {size, index} -> {@first_wave_ms + index * @wave_interval_ms, wave(size)} end)

    [{@assault_ms, %{phase(1) | condition: @event_running}} | waves]
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {delay_ms, step} -> %{step | delay_ms: delay_ms} end)
  end

  defp wave(size) do
    [choice] = CreatureScript.pick(for plagued <- 1..4, do: wave(size, plagued))
    %{choice | condition: @event_running}
  end

  defp wave(size, plagued) do
    cry = talk(@wave_cries)

    [
      %{peasant(@plagued) | dataint2: @cry_script, sub_scripts: %{@cry_script => [cry]}},
      %{peasant(@plagued) | count: plagued - 1},
      %{peasant(@injured) | count: size - plagued}
    ]
  end

  defp peasant(entry), do: %{summon(entry, @peasant_spawn) | scatter: @spawn_scatter}

  defp eris_events do
    assault = CreatureScript.only_in_phases([1])

    [
      CreatureScript.event(@eris, 1, :timer_ooc, footsoldiers(),
        param1: 10_000,
        param2: 14_000,
        param3: 10_000,
        param4: 14_000,
        chance: 85,
        inverse_phase_mask: assault
      ),
      CreatureScript.event(
        @eris,
        2,
        :timer_ooc,
        [
          %ScriptStep{command: :cast_spell, datalong: @blessing_of_nordrassil, target_self?: true},
          %{talk([@eris_heals]) | target_type: :map_event_target, target_param1: @quest}
        ],
        param1: 0,
        param2: 0,
        param3: 75_000,
        param4: 90_000,
        inverse_phase_mask: assault
      )
    ]
  end

  defp footsoldiers do
    CreatureScript.pick(for count <- 2..6, do: List.flatten(List.duplicate(footsoldier(), count)))
  end

  defp footsoldier do
    CreatureScript.pick_weighted(
      for spot <- @footsoldier_spots, {weight, attack} <- [{3, @attack_event_target}, {1, @no_attack}] do
        {weight,
         [%{summon(@footsoldier, spot) | dataint3: attack, target_param1: @quest, scatter: @footsoldier_scatter}]}
      end
    )
  end

  defp peasant_events(entry) do
    lament = [talk(@laments)]

    [
      CreatureScript.event(entry, 1, :spawned, flee(entry)),
      CreatureScript.event(entry, 2, :movement_inform, [walk(@sanctuary, @to_light)],
        param1: @point_motion,
        param2: @to_road
      ),
      CreatureScript.event(entry, 3, :movement_inform, reached_light(), param1: @point_motion, param2: @to_light),
      CreatureScript.event(entry, 4, :death, fallen()),
      CreatureScript.event(
        entry,
        5,
        :hit_by_spell,
        [%ScriptStep{command: :deal_damage, datalong: @arrow_bonus_damage, target_self?: true}],
        param1: @shoot
      ),
      CreatureScript.event(entry, 6, :hit_by_spell, [cast_self(@deaths_door)], param1: @shoot, chance: 9),
      CreatureScript.event(entry, 7, :timer_ooc, lament,
        param1: 10_000,
        param2: 30_000,
        param3: 20_000,
        param4: 50_000,
        chance: 10
      ),
      CreatureScript.event(entry, 8, :timer_in_combat, lament,
        param1: 10_000,
        param2: 30_000,
        param3: 20_000,
        param4: 50_000,
        chance: 10
      )
    ]
  end

  defp flee(entry) do
    plague = if entry == @plagued, do: [cast_self(@seething_plague)], else: []

    [%ScriptStep{command: :set_react_state, datalong: @passive}, join_event()] ++
      plague ++ [walk(@road, @to_road)]
  end

  defp reached_light do
    [tally_step(@saved)] ++
      CreatureScript.pick_weighted([{4, [talk(@farewells)]}, {11, []}]) ++
      [%ScriptStep{command: :despawn}]
  end

  defp fallen do
    posts =
      @death_posts
      |> Enum.with_index()
      |> Enum.map(fn {{entry, position}, index} ->
        %ScriptStep{
          command: :summon_object,
          datalong: entry,
          datalong2: @death_post_s,
          position: position,
          condition: %Condition{type: :map_event_data, value1: @quest, value2: @died, value3: index, value4: 0}
        }
      end)

    hang = CreatureScript.timed(posts)

    [
      %{
        hang
        | target_type: :nearest_game_object_with_entry,
          target_param1: @light,
          target_param2: @field_reach,
          swap_final?: true
      },
      tally_step(@died)
    ]
  end

  defp archer_events do
    volley = volley()

    [
      CreatureScript.event(@archer, 1, :spawned, [
        join_event(),
        %ScriptStep{command: :set_sheath, datalong: @ranged_sheath}
      ]),
      CreatureScript.event(@archer, 2, :timer_ooc, volley, param1: 5_000, param2: 5_000, param3: 3_000, param4: 4_400),
      CreatureScript.event(@archer, 3, :timer_in_combat, volley,
        param1: 3_000,
        param2: 4_400,
        param3: 3_000,
        param4: 4_400
      )
    ]
  end

  defp volley do
    CreatureScript.pick_weighted([{3, [shoot(@injured)]}, {1, [shoot(@plagued)]}])
  end

  defp shoot(entry) do
    %ScriptStep{
      command: :cast_spell,
      datalong: @shoot,
      datalong2: @triggered,
      target_type: :random_creature_with_entry,
      target_param1: entry,
      target_param2: @archer_reach
    }
  end

  defp join_event do
    %ScriptStep{
      command: :add_map_event_target,
      datalong: @quest,
      dataint2: @despawn_script,
      dataint4: @despawn_script,
      sub_scripts: %{@despawn_script => [%ScriptStep{command: :despawn}]}
    }
  end

  defp put_out_light do
    %ScriptStep{
      command: :remove_object,
      target_type: :nearest_game_object_with_entry,
      target_param1: @light,
      target_param2: @light_reach
    }
  end

  defp walk(area, point) do
    %ScriptStep{
      command: :move_to,
      datalong: @random_point,
      datalong3: @pathfind_walk,
      datalong4: @inform,
      dataint: point,
      position: area
    }
  end

  defp summon(entry, position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      dataint3: @no_attack,
      dataint4: @dead_despawn,
      position: position
    }
  end

  defp tally(index, at_least),
    do: %Condition{type: :map_event_data, value1: @quest, value2: index, value3: at_least, value4: 1}

  defp tally_step(index),
    do: %ScriptStep{command: :set_map_event_data, datalong: @quest, datalong2: index, datalong3: 1, datalong4: 1}

  defp talk(text_ids) do
    [:dataint, :dataint2, :dataint3, :dataint4]
    |> Enum.zip(text_ids)
    |> Enum.reduce(%ScriptStep{command: :talk}, fn {field, text_id}, step -> struct!(step, [{field, text_id}]) end)
  end

  defp cast_self(spell_id),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: @triggered, target_self?: true}

  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}
end
