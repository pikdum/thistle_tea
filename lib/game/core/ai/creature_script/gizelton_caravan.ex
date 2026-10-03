defmodule ThistleTea.Game.Core.AI.CreatureScript.GizeltonCaravan do
  @moduledoc """
  vmangos `npc_cork_gizelton` and `npc_rigger_gizelton`, the Gizelton
  Caravan that loops through Desolace behind Gizelton Caravan (5943) and
  Bodyguard for Hire (5821).

  Two seconds after Cork Gizelton spawns, he calls up the caravan, two kodos
  and his brother Rigger, who fall in behind him, and sets off along his
  path. The caravan takes two quests on each loop. On the road east of
  Shadowprey Village, Rigger offers Gizelton Caravan and yells for
  bodyguards across the zone every three minutes; north of the Kolkar
  village, Cork offers Bodyguard for Hire the same way. Ten seconds after a
  player accepts, the caravan moves on, now open to attack, and on that leg
  demons from Mannoroc Coven or Kolkar centaurs ambush it three times. The
  caravan waits out each ambush and credits the player and their group at
  the end of the leg if they are within 100 yards. Nobody signing on within
  fifteen minutes sends the caravan off alone, with no ambushes. If Cork,
  Rigger, or a kodo dies, the caravan disbands and the quest fails.

  Between the legs the caravan camps for ten minutes near Kormek's Hut,
  where Vendor-Tron 1000 opens for business, and at its starting point,
  where Super-Seller 680 does. At the end of its path the caravan despawns,
  and Cork respawns on his own timer to start over.

  Ambushers attack Cork, Rigger, or a random kodo, each by its place in the
  wave, rather than a random member of the caravan each. Each point holds
  the caravan, and spawns its ambushers, before anything Rigger or a vendor
  does: steps another creature runs suspend the rest until it answers, and
  Cork would walk on in the meantime.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @cork 11_625
  @rigger 11_626
  @kodo 11_564
  @vendor_tron 12_245
  @super_seller 12_246
  @doomwarder 4_677
  @nether_sorceress 4_684
  @lesser_infernal 4_676
  @kolkar_ambusher 12_977
  @kolkar_waylayer 12_976

  @bottom 5_943
  @top 5_821

  @legs %{
    @bottom => %{
      giver: @rigger,
      announce: {14, 7_475},
      ambushes: [{28, 7_330}, {34, 7_331}, {40, 7_332}],
      complete: {42, 7_333}
    },
    @top => %{
      giver: @cork,
      announce: {164, 7_474},
      ambushes: [{173, 7_310}, {181, 7_311}, {188, 7_312}],
      complete: {195, 7_334}
    }
  }

  @camps %{141 => {@vendor_tron, @cork, 7_505}, 279 => {@super_seller, @rigger, 7_506}}
  @last_point 281

  @caravan [
    {@kodo, {-1_887.26, 2_465.12, 59.8224, 4.48}, {26.0, 3.14}},
    {@rigger, {-1_883.63, 2_471.68, 59.8224, 4.48}, {18.0, 3.14}},
    {@kodo, {-1_882.11, 2_476.80, 59.8224, 4.48}, {8.0, 3.14}}
  ]

  @waves %{
    @bottom => [{@doomwarder, :cork}, {@nether_sorceress, :kodo}, {@lesser_infernal, :rigger}],
    @top => [
      {@kolkar_ambusher, :cork},
      {@kolkar_waylayer, :kodo},
      {@kolkar_ambusher, :rigger},
      {@kolkar_waylayer, :kodo}
    ]
  }

  @ambush_spots %{
    28 => [
      {-1_799.41, 1_983.18, 59.89},
      {-1_803.8, 1_993.79, 59.2},
      {-1_814.41, 1_998.18, 59.27},
      {-1_825.02, 1_993.79, 59.19},
      {-1_829.41, 1_983.18, 60.33},
      {-1_825.02, 1_972.57, 59.31},
      {-1_814.41, 1_968.18, 59.31},
      {-1_803.8, 1_972.57, 59.49}
    ],
    34 => [
      {-1_736.9, 1_917.2, 59.08},
      {-1_741.29, 1_927.81, 59.28},
      {-1_751.9, 1_932.2, 60.0},
      {-1_762.51, 1_927.81, 58.94},
      {-1_766.9, 1_917.2, 58.93},
      {-1_762.51, 1_906.59, 59.2},
      {-1_751.9, 1_902.2, 59.82},
      {-1_741.29, 1_906.59, 59.12}
    ],
    40 => [
      {-1_669.12, 1_872.66, 59.77},
      {-1_673.51, 1_883.27, 59.63},
      {-1_684.12, 1_887.66, 59.71},
      {-1_694.73, 1_883.27, 59.71},
      {-1_699.12, 1_872.66, 59.51},
      {-1_694.73, 1_862.05, 58.96},
      {-1_684.12, 1_857.66, 58.93},
      {-1_673.51, 1_862.05, 59.05}
    ],
    173 => [
      {-777.51, 1_177.07, 97.7},
      {-781.91, 1_187.68, 98.52},
      {-792.51, 1_192.07, 99.47},
      {-803.12, 1_187.68, 99.57},
      {-807.51, 1_177.07, 99.55},
      {-803.12, 1_166.46, 98.91},
      {-792.51, 1_162.07, 97.07},
      {-781.91, 1_166.46, 97.02}
    ],
    181 => [
      {-916.15, 1_182.17, 93.69},
      {-920.54, 1_192.78, 94.59},
      {-931.15, 1_197.17, 93.95},
      {-941.76, 1_192.78, 91.99},
      {-946.15, 1_182.17, 89.79},
      {-941.76, 1_171.56, 91.51},
      {-931.15, 1_167.17, 94.38},
      {-920.54, 1_171.56, 93.77}
    ],
    188 => [
      {-1_058.62, 1_186.33, 89.75},
      {-1_063.01, 1_196.94, 89.75},
      {-1_073.62, 1_201.33, 89.74},
      {-1_084.23, 1_196.94, 89.74},
      {-1_088.62, 1_186.33, 89.74},
      {-1_084.23, 1_175.72, 89.77},
      {-1_073.62, 1_171.33, 90.39},
      {-1_063.01, 1_175.72, 90.52}
    ]
  }

  @init_delay_ms 2_000
  @depart_delay_ms 10_000
  @announce_interval_ms 180_000
  @announcements 5
  @announce_ms 900_000
  @camp_ms 600_000
  @ambush_ms 400_000
  @ambusher_ms 30_000
  @event_limit_s 3_600
  @credit_distance 100

  @script_route 5
  @member_script 1
  @group_script 1
  @failure_script 1
  @hold_release_script 1
  @signal_hold 1
  @start_for_cork 1
  @creatures 2
  @cork_reach 100
  @member_reach 60
  @vendor_reach 100

  @npc_flags_field 147
  @unit_flags_field 46
  @questgiver 0x2
  @all_flags 0xFFFF_FFFF
  @immune_to_npc 0x200
  @add_flags 1
  @remove_flags 2
  @escort_faction 495
  @formation_move_and_aggro 0x3
  @zone_yell 6
  @source_dead 1
  @dead_despawn 7
  @timed_or_dead_despawn 1

  @attack_self 8
  @attack_nearest 10
  @attack_random 28

  @impl CreatureScript
  def entries, do: [@cork]

  @impl CreatureScript
  def events(@cork) do
    [
      CreatureScript.event(@cork, 1, :spawned, [CreatureScript.timed(Enum.map(setup(), &delay(&1, @init_delay_ms)))]),
      CreatureScript.event(@cork, 2, :summoned_just_died, disband(), param1: @rigger),
      CreatureScript.event(@cork, 3, :summoned_just_died, disband(), param1: @kodo),
      CreatureScript.event(@cork, 4, :death, disband())
    ]
  end

  @impl CreatureScript
  def quest_start_steps do
    %{
      @bottom => [
        %ScriptStep{
          command: :start_script_for_all,
          datalong: @start_for_cork,
          datalong2: @creatures,
          datalong3: @cork,
          datalong4: @cork_reach,
          sub_scripts: %{@start_for_cork => accept(@bottom)}
        }
      ],
      @top => accept(@top)
    }
  end

  @impl CreatureScript
  def routes do
    legs =
      Enum.flat_map(@legs, fn {quest, leg} ->
        {announce_point, announce_text} = leg.announce
        {complete_point, complete_text} = leg.complete

        [{announce_point, announce(quest, announce_text)}, {complete_point, complete(quest, complete_text)}] ++
          Enum.map(leg.ambushes, fn {point, text} -> {point, ambush(quest, point, text)} end)
      end)

    camps = Enum.map(@camps, fn {point, {vendor, speaker, text}} -> {point, camp(vendor, speaker, text)} end)

    %{@cork => Map.new(legs ++ camps ++ [{@last_point, [on_caravan([%ScriptStep{command: :despawn}])]}])}
  end

  defp setup do
    [npc_flags(@remove_flags, @all_flags)] ++
      Enum.map(@caravan, fn {entry, position, formation} -> member(entry, position, formation) end) ++
      [%ScriptStep{command: :start_waypoints, datalong: @script_route}]
  end

  defp member(entry, position, {distance, angle}) do
    join = %ScriptStep{
      command: :join_creature_group,
      datalong: @formation_move_and_aggro,
      position: {distance, 0.0, 0.0, angle},
      target_type: :nearest_creature_with_entry,
      target_param1: @cork,
      target_param2: @member_reach
    }

    steps = if entry == @rigger, do: [join, npc_flags(@remove_flags)], else: [join]

    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      dataint2: @member_script,
      dataint3: -1,
      dataint4: @dead_despawn,
      position: position,
      sub_scripts: %{@member_script => steps}
    }
  end

  defp announce(quest, text) do
    giver = @legs[quest].giver

    yells =
      for index <- 0..(@announcements - 1) do
        quest
        |> speak(text, @zone_yell)
        |> delay(index * @announce_interval_ms)
        |> then(&%{&1 | condition: %Condition{type: :has_flag, value1: @npc_flags_field, value2: @questgiver}})
      end

    [hold(@announce_ms, @signal_hold, [by(giver, npc_flags(@remove_flags)), on_caravan(depart())])] ++
      [by(giver, npc_flags(@add_flags))] ++ yells
  end

  defp accept(quest) do
    [
      %ScriptStep{
        command: :start_map_event,
        datalong: quest,
        datalong2: @event_limit_s,
        dataint4: @failure_script,
        abort_on_failure?: true,
        failure_condition: %Condition{type: :escort, value1: @source_dead},
        sub_scripts: %{@failure_script => [%ScriptStep{command: :fail_quest, datalong: quest}]}
      },
      by(@legs[quest].giver, npc_flags(@remove_flags)),
      %ScriptStep{command: :release_waypoints, delay_ms: @depart_delay_ms}
    ]
  end

  defp ambush(quest, point, text) do
    escorted = %Condition{type: :map_event_active, value1: quest}
    positions = Map.fetch!(@ambush_spots, point)
    summons = Enum.map(@waves[quest], fn {entry, victim} -> ambusher(entry, victim, positions) end)

    ([hold(@ambush_ms, 0, [])] ++ summons ++ [speak(quest, text)])
    |> Enum.map(&%{&1 | condition: escorted})
  end

  defp ambusher(entry, victim, positions) do
    {attack, entry_param} =
      case victim do
        :cork -> {@attack_self, 0}
        :kodo -> {@attack_random, @kodo}
        :rigger -> {@attack_nearest, @rigger}
      end

    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @ambusher_ms,
      dataint3: attack,
      dataint4: @timed_or_dead_despawn,
      target_param1: entry_param,
      target_param2: if(entry_param == 0, do: 0, else: @member_reach),
      positions: Enum.map(positions, fn {x, y, z} -> {x, y, z, 0.0} end)
    }
  end

  defp complete(quest, text) do
    [
      %{speak(quest, text) | condition: %Condition{type: :map_event_active, value1: quest}},
      %ScriptStep{
        command: :quest_explored,
        datalong: quest,
        datalong2: @credit_distance,
        datalong3: 1,
        target_type: :map_event_target,
        target_param1: quest
      },
      %ScriptStep{command: :end_map_event, datalong: quest, datalong2: 1},
      on_caravan([
        %ScriptStep{command: :set_faction, datalong: 0},
        %ScriptStep{
          command: :modify_flags,
          datalong: @unit_flags_field,
          datalong2: @immune_to_npc,
          datalong3: @add_flags
        }
      ]),
      %ScriptStep{command: :set_run, datalong: 1}
    ]
  end

  defp depart do
    [
      %ScriptStep{command: :set_faction, datalong: @escort_faction},
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_flags_field,
        datalong2: @immune_to_npc,
        datalong3: @remove_flags
      }
    ]
  end

  defp camp(vendor, speaker, leave_text) do
    [
      %ScriptStep{command: :set_run, datalong: 0},
      hold(@camp_ms, @signal_hold, [by(speaker, talk(leave_text)), vendor_visibility(vendor, true)]),
      vendor_visibility(vendor, false)
    ]
  end

  defp disband do
    Enum.map([@bottom, @top], &%ScriptStep{command: :end_map_event, datalong: &1}) ++
      [on_caravan([%ScriptStep{command: :despawn}])]
  end

  defp vendor_visibility(vendor, concealed?) do
    %ScriptStep{
      command: :set_concealed,
      datalong: if(concealed?, do: 1, else: 0),
      target_type: :nearest_creature_with_entry,
      target_param1: vendor,
      target_param2: @vendor_reach,
      swap_final?: true
    }
  end

  defp hold(duration_ms, mode, release) do
    %ScriptStep{
      command: :hold_waypoints,
      datalong: duration_ms,
      datalong2: mode,
      sub_scripts: %{@hold_release_script => release}
    }
  end

  defp on_caravan(steps) do
    %ScriptStep{
      command: :start_script_on_group,
      datalong: @group_script,
      dataint: 100,
      sub_scripts: %{@group_script => steps}
    }
  end

  defp speak(quest, text, chat_type \\ 0), do: by(@legs[quest].giver, %{talk(text) | datalong: chat_type})

  defp talk(text), do: %ScriptStep{command: :talk, dataint: text}

  defp by(@cork, step), do: step

  defp by(entry, step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @member_reach,
        swap_final?: true
    }
  end

  defp npc_flags(mode, flags \\ @questgiver),
    do: %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: flags, datalong3: mode}

  defp delay(%ScriptStep{} = step, delay_ms), do: %{step | delay_ms: delay_ms}
end
