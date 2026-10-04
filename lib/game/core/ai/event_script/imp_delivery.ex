defmodule ThistleTea.Game.Core.AI.EventScript.ImpDelivery do
  @moduledoc """
  vmangos `npc_j_eevee_scholomanceAI`, Imp Delivery (7629): the Release Imp
  event (8438) that opening the Imp in a Jar sends in Scholomance's
  alchemy lab.

  The warlock kneels and J'eevee gets loose. She wanders the lab benches for
  half a minute, stopping three times to knock something over, then credits
  the warlock with her delivery, teleports, and vanishes. vmangos sends her
  to each point once she reaches the last; here each move starts when a
  walk, or a run on the dash between the benches, at her speed lands.
  """

  @behaviour ThistleTea.Game.Core.AI.EventScript

  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @event 8_438
  @jeevee 14_500
  @spawn {38.62, 161.78, 83.5456, 4.69993}
  @lifetime_ms 180_000
  @no_attack -1
  @timed_or_dead_despawn 1
  @script 1

  @kneel 16
  @attack_unarmed 35
  @teleport 7_791
  @triggered 0x02
  @pathfind 0x1
  @walk 0x2
  @run 0x4
  @walk_speed 2.5
  @run_speed 8.0
  @first_move_ms 4_000
  @swing_every_ms 1_000

  @texts %{0 => 9_769, 3 => 9_770, 8 => 9_771, 12 => 9_742}

  @path [
    {{38.123325, 159.745956, 83.545631, 1.587492}, 300},
    {{36.478260, 160.530975, 83.545631, 3.179874}, 4_000},
    {{38.123325, 159.745956, 83.545631, 5.250862}, 100},
    {{41.213757, 155.202774, 83.545631, 0.098650}, 50},
    {{45.890804, 155.115601, 83.545631, 0.018146}, 50},
    {{46.639896, 160.362015, 83.545631, 2.549089}, 50},
    {{44.227440, 160.631088, 83.545631, 2.549089}, 4_000},
    {{46.639896, 160.362015, 83.545631, 5.250862}, 300},
    {{46.425823, 154.547577, 83.645631, 3.108989}, 50},
    {{34.415833, 154.561859, 83.645631, 3.140403}, 50},
    {{28.838001, 160.411469, 83.645631, 2.378568}, 100},
    {{33.201927, 160.234833, 83.645624, 6.242730}, 4_000},
    {{33.201927, 160.234833, 83.645624, 6.242730}, 2_000}
  ]
  @running 9..11
  @swinging [2, 7, 12]
  @finale 13

  @impl EventScript
  def event_ids, do: [@event]

  @impl EventScript
  def event_steps(@event) do
    [
      %ScriptStep{command: :emote, datalong: @kneel},
      %ScriptStep{
        command: :summon_creature,
        datalong: @jeevee,
        datalong2: @lifetime_ms,
        dataint2: @script,
        dataint3: @no_attack,
        dataint4: @timed_or_dead_despawn,
        position: @spawn,
        target_self?: true,
        sub_scripts: %{@script => wander()}
      }
    ]
  end

  def wander do
    {steps, _position, done_ms} =
      @path
      |> Enum.with_index(1)
      |> Enum.reduce({[], @spawn, @first_move_ms}, fn {{point, wait_ms}, index}, {steps, from, depart_ms} ->
        running? = index in @running
        arrive_ms = depart_ms + travel_ms(from, point, running?)
        departure = at(depart_ms, departure(index - 1) ++ [move(point, running?)])
        arrival = at(arrive_ms, arrival(index, wait_ms))
        {steps ++ departure ++ arrival, point, arrive_ms + wait_ms}
      end)

    Enum.sort_by(steps ++ at(done_ms, [%ScriptStep{command: :despawn}]), & &1.delay_ms)
  end

  defp departure(12), do: [talk(12), %ScriptStep{command: :kill_credit, datalong: @jeevee}]
  defp departure(index) when is_map_key(@texts, index), do: [talk(index)]
  defp departure(_index), do: []

  defp arrival(index, wait_ms) when index in @swinging do
    for offset <- 0..(wait_ms - 1)//@swing_every_ms,
        do: %ScriptStep{command: :emote, datalong: @attack_unarmed, delay_ms: offset}
  end

  defp arrival(@finale, _wait_ms),
    do: [%ScriptStep{command: :cast_spell, datalong: @teleport, datalong2: @triggered, target_self?: true}]

  defp arrival(_index, _wait_ms), do: []

  defp move(position, running?),
    do: %ScriptStep{
      command: :move_to,
      datalong3: Bitwise.bor(@pathfind, if(running?, do: @run, else: @walk)),
      position: position
    }

  defp travel_ms({x1, y1, z1, _o1}, {x2, y2, z2, _o2}, running?) do
    distance = :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2 + (z2 - z1) ** 2)
    round(distance / if(running?, do: @run_speed, else: @walk_speed) * 1_000)
  end

  defp at(base_ms, steps), do: Enum.map(steps, &%{&1 | delay_ms: base_ms + &1.delay_ms})

  defp talk(index), do: %ScriptStep{command: :talk, dataint: Map.fetch!(@texts, index)}
end
