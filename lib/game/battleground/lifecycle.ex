defmodule ThistleTea.Game.Battleground.Lifecycle do
  @moduledoc "Shared countdown, resurrection, scoreboard, and departure rules for battleground matches."

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Result

  @resurrection_wave_ms 30_000
  @auto_leave_ms 120_000

  def start_timers(delay) do
    [{:start, delay}, {:resurrection_wave, delay}]
    |> add_countdown(:start_one_minute, delay - 60_000)
    |> add_countdown(:start_half_minute, delay - 30_000)
  end

  def handle_timer(%{phase: :active} = match, :status_refresh, _now, scoreboard) do
    %Result{match: match, effects: [%Effects.UpdateStatus{}, scoreboard]}
  end

  def handle_timer(%{phase: phase} = match, :resurrection_wave, now, _scoreboard) when phase in [:countdown, :active] do
    guids = match.resurrection_queue |> MapSet.to_list() |> Enum.sort()
    effects = if guids == [], do: [], else: [%Effects.ResurrectPlayers{guids: guids}]

    %Result{
      match: %{match | resurrection_queue: MapSet.new(), next_resurrection_at: now + @resurrection_wave_ms},
      effects: effects,
      timers: [resurrection_wave: @resurrection_wave_ms]
    }
  end

  def handle_timer(%{phase: {:ended, _winner}} = match, :auto_leave, _now, _scoreboard) do
    destinations =
      match.players
      |> Map.values()
      |> Enum.filter(&(&1.status in [:inside, :offline] and not is_nil(&1.return_to)))
      |> Map.new(&{&1.guid, &1.return_to})

    %Result{match: match, effects: [%Effects.ExitPlayers{destinations: destinations}]}
  end

  def handle_timer(match, _key, _now, _scoreboard), do: %Result{match: match}

  def scoreboard_snapshot(match, players) do
    case match.phase do
      {:ended, winner} -> %Effects.Scoreboard{ended?: true, winner: winner, players: players}
      _active -> %Effects.Scoreboard{ended?: false, players: players}
    end
  end

  def auto_leave_ms(%{ended_at: ended_at}, now) when is_integer(ended_at), do: max(ended_at + @auto_leave_ms - now, 0)

  def auto_leave_ms(_match, _now), do: 0

  def next_resurrection_ms(%{next_resurrection_at: at}, now) when is_integer(at), do: max(at - now, 0)
  def next_resurrection_ms(_match, _now), do: @resurrection_wave_ms

  def finish(match, winner, now, effects, scoreboard) do
    match = %{match | phase: {:ended, winner}, ended_at: now, resurrection_queue: MapSet.new()}
    participants = match.players |> Map.values() |> Enum.filter(&(&1.status == :inside))

    %Result{
      match: match,
      effects:
        effects ++
          [
            %Effects.UpdateStatus{},
            scoreboard_snapshot(match, scoreboard),
            %Effects.RewardPlayers{winner: winner, players: participants}
          ],
      timers: [auto_leave: @auto_leave_ms]
    }
  end

  def team_graveyard(template, :alliance), do: template.alliance_graveyard || template.alliance_start
  def team_graveyard(template, :horde), do: template.horde_graveyard || template.horde_start

  defp add_countdown(timers, _key, delay) when delay <= 0, do: timers
  defp add_countdown(timers, key, delay), do: [{key, delay} | timers]
end
