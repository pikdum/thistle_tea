defmodule ThistleTea.Game.Core.AI.CreatureScript.TwiggyFlathead do
  @moduledoc """
  vmangos `npc_twiggy_flathead`, who runs The Affray (1719) in the Barrens
  ring. A warrior stepping into the ring with the quest
  (`AreaTriggerScript.TwiggyFlathead`) starts the fight: six challengers
  gather, then come at the player one every twenty-five seconds, and Big Will
  walks in after the last. Twiggy calls each challenger down and declares
  the Affray over when Big Will falls, while the spectators cheer and jeer.

  Twiggy keeps one Affray at a time, until Big Will dies or leaves. Unlike
  vmangos, the fight runs its course if the player dies or leaves the ring
  part way, rather than stalling with the challengers still standing there.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @twiggy 6248
  @big_will 6238
  @challenger 6240
  @spectator 6249
  @begin 1
  @affray_has_begun 2301
  @enter_the_fray 2318
  @challenger_is_down 2355
  @affray_is_over 2320
  @ready_when_you_are 2421
  @friendly 35
  @monster 16
  @creature 7
  @roar 15
  @cheer 4
  @rude 14
  @idle 0
  @fighting 1
  @gather_ms 2_000
  @first_fray_ms 5_000
  @fray_interval_ms 25_000
  @big_will_wait_ms 15_000
  @challenger_stay_ms 600_000
  @big_will_stay_ms 300_000
  @no_attack -1
  @timed_or_dead_despawn 1
  @pathfind 1
  @crowd_radius 30

  @challengers [
    {-1683.0, -4326.0, 2.79, 0.00},
    {-1682.0, -4329.0, 2.79, 0.00},
    {-1683.0, -4330.0, 2.79, 0.00},
    {-1680.0, -4334.0, 2.79, 1.49},
    {-1674.0, -4326.0, 2.79, 3.49},
    {-1677.0, -4334.0, 2.79, 1.66}
  ]
  @big_will_arrival {-1713.79, -4342.09, 6.05, 6.15}
  @ring {-1682.31, -4329.68, 2.78, 0.0}

  def begin_event, do: @begin

  @impl CreatureScript
  def entries, do: [@twiggy]

  @impl CreatureScript
  def events(entry) do
    idle = CreatureScript.only_in_phases([@idle])
    fighting = CreatureScript.only_in_phases([@fighting])

    [
      CreatureScript.event(entry, 1, :script_event, begin(), param1: @begin, inverse_phase_mask: idle),
      CreatureScript.event(entry, 2, :summoned_just_died, [talk(@challenger_is_down)], param1: @challenger),
      CreatureScript.event(entry, 3, :summoned_just_died, [talk(@affray_is_over), phase(@idle)], param1: @big_will),
      CreatureScript.event(entry, 4, :summoned_just_despawn, [phase(@idle)], param1: @big_will),
      CreatureScript.event(entry, 5, :timer_ooc, [crowd()],
        param1: 1_000,
        param2: 1_000,
        param3: 2_000,
        param4: 2_000,
        inverse_phase_mask: fighting
      )
    ]
  end

  defp begin do
    frays =
      for index <- 0..(length(@challengers) - 1) do
        %{talk(@enter_the_fray) | delay_ms: fray_ms(index) + @gather_ms}
      end

    [
      phase(@fighting),
      talk(@affray_has_begun),
      CreatureScript.timed(
        challengers() ++ frays ++ [%{big_will() | delay_ms: fray_ms(length(@challengers)) + @gather_ms}]
      )
    ]
  end

  defp challengers do
    @challengers
    |> Enum.with_index(1)
    |> Enum.map(fn {position, script_id} ->
      summon(@challenger, position, @challenger_stay_ms, script_id, [
        CreatureScript.faction(@friendly),
        roar(),
        %{CreatureScript.faction(@monster) | delay_ms: fray_ms(script_id - 1)},
        %{roar() | delay_ms: fray_ms(script_id - 1)}
      ])
      |> Map.put(:delay_ms, @gather_ms)
    end)
  end

  defp big_will do
    summon(@big_will, @big_will_arrival, @big_will_stay_ms, 1, [
      CreatureScript.faction(@friendly),
      %ScriptStep{command: :move_to, datalong3: @pathfind, position: @ring},
      %{CreatureScript.faction(@creature) | delay_ms: @big_will_wait_ms},
      %{talk(@ready_when_you_are) | delay_ms: @big_will_wait_ms}
    ])
  end

  defp summon(entry, position, stay_ms, script_id, steps) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: stay_ms,
      dataint2: script_id,
      dataint3: @no_attack,
      dataint4: @timed_or_dead_despawn,
      position: position,
      sub_scripts: %{script_id => steps}
    }
  end

  defp crowd do
    %ScriptStep{
      command: :emote,
      datalong: @cheer,
      datalong2: @rude,
      target_type: :random_creature_with_entry,
      target_param1: @spectator,
      target_param2: @crowd_radius,
      swap_final?: true
    }
  end

  defp fray_ms(index), do: @first_fray_ms + index * @fray_interval_ms

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp roar, do: %ScriptStep{command: :emote, datalong: @roar}
  defp phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
end
