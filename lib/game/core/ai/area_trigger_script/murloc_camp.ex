defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.MurlocCamp do
  @moduledoc """
  vmangos `at_murloc_camp`: a living player on WANTED: Murkdeep! (4740)
  reaching the bonfire at the Greymist camp on Darkshore's Twilight Shore
  draws Murkdeep out, unless he is already about. Murkdeep waits unseen in
  the shallows and sends the Greymist ashore at the player in three waves
  thirty seconds apart: three coastrunners, then two warriors, then a hunter,
  with Murkdeep himself joining the last wave. The murlocs leave ten minutes
  after their fight unless killed, and Murkdeep after half an hour. If the
  player dies or strays more than fifty yards from the bonfire before a wave,
  Murkdeep slips away and the rest of the event is called off.

  vmangos keeps the waiting Murkdeep out of sight entirely. Here he wears the
  invisible trigger model and cannot be selected until he steps out.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @murloc_camp 1966
  @wanted_murkdeep 4740
  @incomplete 1

  @murkdeep 10_323
  @coastrunner 2_202
  @warrior 2_205
  @hunter 2_206

  @murkdeep_ms 1_800_000
  @murloc_ms 600_000
  @unique_limit 1
  @unique_distance 100
  @unique 0x04
  @no_attack -1
  @attack_player 0
  @timed_or_dead_despawn 1
  @event_script 1

  @invisible_model 11_686
  @demorph 0
  @by_model 1
  @unit_flags 46
  @hidden_flags 0x0200_0300
  @add_flags 1
  @remove_flags 2
  @passive 0
  @aggressive 2

  @first_wave_ms 1_000
  @wave_interval_ms 30_000
  @bonfire {4_988.28, 547.688, 5.11441}
  @bonfire_reach 50
  @facing 4.8

  @shallows [
    {4_984.772, 596.975, -1.172},
    {4_989.618, 599.530, -1.291},
    {4_979.620, 593.845, -0.881}
  ]

  @impl AreaTriggerScript
  def triggers, do: [@murloc_camp]

  @impl AreaTriggerScript
  def steps(@murloc_camp, _position) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @murkdeep,
        datalong2: @murkdeep_ms,
        datalong3: @unique_limit,
        datalong4: @unique_distance,
        dataint: @unique,
        dataint2: @event_script,
        dataint3: @no_attack,
        dataint4: @timed_or_dead_despawn,
        position: shallows(0),
        sub_scripts: %{@event_script => hide() ++ waves()},
        condition: %Condition{
          type: :and,
          children: [
            %Condition{type: :quest_taken, value1: @wanted_murkdeep, value2: @incomplete},
            %Condition{type: :alive}
          ]
        }
      }
    ]
  end

  defp hide do
    [
      %ScriptStep{command: :morph, datalong: @invisible_model, datalong2: @by_model},
      unit_flags(@add_flags),
      %ScriptStep{command: :set_react_state, datalong: @passive}
    ]
  end

  defp waves do
    [
      {0, [murloc(@coastrunner, 0), murloc(@coastrunner, 1), murloc(@coastrunner, 2)]},
      {1, [murloc(@warrior, 0), murloc(@warrior, 1)]},
      {2, [murloc(@hunter, 1) | step_out()]}
    ]
    |> Enum.flat_map(fn {wave, steps} ->
      delay_ms = @first_wave_ms + wave * @wave_interval_ms
      slip_away = %ScriptStep{command: :despawn, condition: %{player_present() | reverse?: true}}
      Enum.map([slip_away | Enum.map(steps, &%{&1 | condition: player_present()})], &%{&1 | delay_ms: delay_ms})
    end)
  end

  defp step_out do
    [
      %ScriptStep{command: :morph, datalong: @demorph},
      unit_flags(@remove_flags),
      %ScriptStep{command: :set_react_state, datalong: @aggressive},
      %ScriptStep{command: :attack_start}
    ]
  end

  defp murloc(entry, point) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @murloc_ms,
      dataint3: @attack_player,
      dataint4: @timed_or_dead_despawn,
      position: shallows(point)
    }
  end

  defp shallows(point) do
    {x, y, z} = Enum.at(@shallows, point)
    {x, y, z, @facing}
  end

  defp unit_flags(mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: @hidden_flags, datalong3: mode}

  defp player_present do
    {x, y, z} = @bonfire

    %Condition{
      type: :and,
      children: [
        %Condition{type: :alive},
        %Condition{type: :distance_to_position, value1: x, value2: y, value3: z, value4: @bonfire_reach}
      ]
    }
  end
end
