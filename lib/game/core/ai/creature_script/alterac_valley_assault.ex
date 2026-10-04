defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyAssault do
  @moduledoc """
  Alterac Valley's world-boss summoners, their escorts, and Ivus and Lokholar.
  Team offerings start the summoners' script-waypoint routes. Their escorts
  mount alongside them and join the invocation at the altar. The completion
  spell raises the boss and sends a script event to the summoner, who accepts
  it once while at the altar. Summoners and escorts leave afterward while the
  boss follows its own route and fights through vmangos's spell timers.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @thurloga 13_236
  @renferal 13_442
  @shaman 13_284
  @druid 13_443
  @lokholar 13_256
  @ivus 13_419
  @call_lokholar 7_060
  @call_ivus 7_268
  @invocation 11_206
  @marching 1
  @mounted 2
  @invoking 3
  @summoned 4
  @script_route 5
  @creatures 2
  @script 1
  @triggered 0x02
  @aura_not_present 0x20
  @display_id 1
  @unattached 1
  @unit_flags_field 46
  @immune_to_player 0x100
  @spawning 0x1
  @pvp 0x1000
  @remove_flags 2
  @add_flags 1
  @horde_altar {-360.139, -133.403, 26.4856, 4.41568}
  @alliance_altar {-199.993, -343.217, 6.77662, 3.68265}
  @boss_home {-260.0, -290.0, 6.7, 0.0}

  @impl true
  def entries, do: [@thurloga, @renferal, @shaman, @druid, @lokholar, @ivus]

  @impl true
  def events(@thurloga = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [mount(0), Combat.cast(15_786, :self)]),
      Combat.every(entry, 2, Combat.cast(16_006), 10_000, {15_000, 18_000}),
      Combat.every(entry, 3, Combat.cast(15_616), 5_000, {8_000, 9_000}),
      Combat.every(entry, 4, Combat.cast(15_234), 7_500, {11_000, 12_000}),
      Combat.below_health(entry, 5, Combat.cast(12_492, :self), 70, 7_000),
      Combat.every(entry, 6, Combat.cast(15_786, :self), 0, 14_000,
        condition: %Condition{type: :nearby_creature, value1: 2_630, value2: 20, reverse?: true, swap_targets?: true}
      )
    ] ++ summoner_events(entry, 7, @shaman, 12_242, @call_lokholar, @lokholar, 600_000)
  end

  def events(@renferal = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [mount(0)]),
      Combat.every(entry, 2, Combat.cast(22_127), 3_000, {9_000, 13_000}),
      Combat.every(entry, 3, Combat.cast(15_981, :self, @triggered), 10_000, 17_000, check_result?: false),
      Combat.every(entry, 4, Combat.cast(21_668), 0, 7_000, check_result?: false)
    ] ++ summoner_events(entry, 5, @druid, 9_695, @call_ivus, @ivus, 6_000)
  end

  def events(@shaman = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [Combat.cast(12_550, :self, @triggered)]),
      CreatureScript.event(entry, 2, :aggro, [mount(0), interrupt(), remove_invocation()]),
      Combat.every(entry, 3, Combat.cast(21_401), 5_000, {5_000, 6_000}),
      Combat.below_health(entry, 4, Combat.cast(12_492, :self), 70, 7_000),
      Combat.every(entry, 5, Combat.cast(12_550, :self, @aura_not_present), 9_000, {9_000, 11_000})
    ] ++ recover(entry, 6, 1_166)
  end

  def events(@druid = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [Combat.cast(22_128, :self, @triggered)]),
      CreatureScript.event(entry, 2, :aggro, [mount(0), interrupt(), remove_invocation()]),
      Combat.every(entry, 3, Combat.cast(22_127), 3_000, {9_000, 13_000}),
      Combat.every(entry, 4, Combat.cast(21_668), 0, {7_000, 9_500})
    ] ++ recover(entry, 5, 9_695)
  end

  def events(@lokholar = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, boss_arrival(8_616, 8_617)),
      Combat.every(entry, 2, Combat.cast(21_367), 10_000, {10_000, 12_000}),
      Combat.every(entry, 3, Combat.cast(21_369), 1_000, {4_500, 6_500}),
      Combat.every(entry, 4, Combat.cast(14_907), 8_500, {8_000, 12_000}),
      Combat.every(entry, 5, Combat.cast(19_133), 4_000, {3_000, 5_000}),
      Combat.every(entry, 6, Combat.cast(15_878), 9_000, {10_000, 12_000}),
      Combat.every(entry, 7, Combat.cast(16_869), 5_500, {8_000, 12_000}),
      CreatureScript.event(entry, 8, :kill, [Combat.talk(8_618), Combat.cast(21_307, :self, @triggered)], param3: 1)
    ]
  end

  def events(@ivus = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, boss_arrival(8_736)),
      Combat.every(entry, 2, Combat.cast(20_654, :self), 8_500, {6_000, 8_000}),
      Combat.every(entry, 3, Combat.cast(21_670), 5_500, {3_000, 7_000}),
      Combat.every(entry, 4, Combat.cast(21_669), 7_000, {8_000, 12_000}),
      Combat.every(entry, 5, Combat.cast(21_668), 10_000, {3_000, 7_000}),
      Combat.every(entry, 6, Combat.cast(21_667), 1_000, {1_000, 3_000})
    ]
  end

  @impl true
  def routes do
    [
      %Route{
        entry: @thurloga,
        points: %{
          0 => depart(),
          6 => mounted(@shaman, 12_242, 1_166),
          42 => on_foot(@shaman),
          43 => altar(@shaman, 8_632, 178_465, @horde_altar)
        }
      },
      %Route{
        entry: @renferal,
        points: %{
          0 => depart(),
          3 => mounted(@druid, 9_695, 9_695),
          48 => on_foot(@druid),
          49 => altar(@druid, 8_735, 178_670, @alliance_altar)
        }
      },
      %Route{
        entry: @lokholar,
        points: %{
          30 => [Combat.talk(8_740), home()],
          31 => [home(), stop()]
        }
      },
      %Route{
        entry: @ivus,
        points: %{
          1 => [Combat.talk(8_737)],
          21 => [Combat.talk(8_739), home(), stop()]
        }
      }
    ]
  end

  defp summoner_events(entry, index, escort, display, event, boss, cleanup_ms) do
    recover(entry, index, display) ++
      [
        CreatureScript.event(entry, index + 2, :script_event, complete(escort, boss, cleanup_ms),
          param1: event,
          condition: %Condition{type: :alive, swap_targets?: true},
          inverse_phase_mask: CreatureScript.only_in_phases([@invoking])
        )
      ]
  end

  defp recover(entry, index, display) do
    [
      CreatureScript.event(entry, index, :evade, [mount(display)],
        inverse_phase_mask: CreatureScript.only_in_phases([@mounted])
      ),
      CreatureScript.event(entry, index + 1, :evade, [invoke()],
        inverse_phase_mask: CreatureScript.only_in_phases([@invoking])
      )
    ]
  end

  defp depart do
    [
      phase(@marching),
      unit_flags(@spawning + @immune_to_player, @remove_flags),
      unit_flags(@pvp, @add_flags),
      run(false)
    ]
  end

  defp mounted(escort, display, escort_display),
    do: [
      phase(@mounted),
      mount(display),
      run(true),
      escorts(escort, 40, [phase(@mounted), mount(escort_display), run(true)])
    ]

  defp on_foot(escort),
    do: [phase(@marching), mount(0), run(false), escorts(escort, 40, [phase(@marching), mount(0), run(false)])]

  defp altar(escort, text, entry, position) do
    [
      phase(@invoking),
      home(),
      stop(),
      Combat.talk(text),
      %ScriptStep{command: :summon_object, datalong: entry, datalong3: @unattached, position: position},
      invoke(),
      escorts(escort, 30, [phase(@invoking), invoke()])
    ]
  end

  defp complete(escort, boss, cleanup_ms) do
    cleanup =
      CreatureScript.timed([
        %{escorts(escort, 100, [mount(0), %ScriptStep{command: :despawn}]) | delay_ms: cleanup_ms},
        %ScriptStep{command: :despawn, delay_ms: cleanup_ms}
      ])

    announcement = if boss == @lokholar, do: [Combat.talk(8_626)], else: []

    [
      phase(@summoned),
      interrupt(),
      remove_invocation(),
      escorts(escort, 200, [phase(@summoned), interrupt(), remove_invocation()]),
      remove_altar(boss),
      cleanup
    ] ++ announcement
  end

  defp boss_arrival(text, second_text \\ nil) do
    steps = [%ScriptStep{command: :start_waypoints, datalong: @script_route, delay_ms: 1_000}]
    steps = if second_text, do: steps ++ [%{Combat.talk(second_text) | delay_ms: 3_000}], else: steps

    [
      Combat.talk(text),
      %ScriptStep{command: :set_home_position, position: @boss_home},
      run(false),
      CreatureScript.timed(steps)
    ]
  end

  defp escorts(entry, radius, steps) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @script,
      datalong2: @creatures,
      datalong3: entry,
      datalong4: radius,
      sub_scripts: %{@script => steps}
    }
  end

  defp unit_flags(flags, mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: flags, datalong3: mode}

  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
  defp mount(display), do: %ScriptStep{command: :mount, datalong: display, datalong2: @display_id}
  defp run(run?), do: %ScriptStep{command: :set_run, datalong: if(run?, do: 1, else: 0)}
  defp home, do: %ScriptStep{command: :set_home_position, datalong: 1}
  defp stop, do: %ScriptStep{command: :movement, datalong: 0}
  defp invoke, do: Combat.cast(@invocation, :self, @triggered)
  defp interrupt, do: %ScriptStep{command: :interrupt_casts, datalong: @invocation}
  defp remove_invocation, do: %ScriptStep{command: :remove_aura, datalong: @invocation, datalong2: 1}

  defp remove_altar(boss) do
    %ScriptStep{
      command: :remove_object,
      target_type: :nearest_game_object_with_entry,
      target_param1: if(boss == @ivus, do: 178_670, else: 178_465),
      target_param2: 50,
      swap_final?: true
    }
  end
end
