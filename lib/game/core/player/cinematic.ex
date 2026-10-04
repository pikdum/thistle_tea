defmodule ThistleTea.Game.Core.Player.Cinematic do
  @moduledoc """
  A first login's intro cinematic, whose camera the server follows so the
  creatures it flies past are sent to the client, as vmangos does. Its clock
  starts once the player is in the world. The camera sits on the latest
  waypoint it has passed, or on the starting waypoint before then, and the
  view returns to the player whenever the camera is back in line with them.
  A camera the client never reports finished stops following its path a few
  seconds after the last waypoint.
  """

  defstruct [:sequence_id, :started_at, :start, waypoints: []]

  @ends_after_ms 5_000
  @in_line_squared 20.0

  def prepare(sequence_id, waypoints, {x, y, z, _orientation}),
    do: %__MODULE__{sequence_id: sequence_id, start: {x, y, z}, waypoints: waypoints}

  def begin(%__MODULE__{started_at: nil} = cinematic, now), do: %{cinematic | started_at: now}
  def begin(%__MODULE__{} = cinematic, _now), do: cinematic

  def camera(%__MODULE__{started_at: started_at} = cinematic, now) when is_integer(started_at) do
    elapsed = now - started_at

    cond do
      elapsed > end_at(cinematic) -> :finished
      position = position(cinematic.waypoints, elapsed) -> view(cinematic.start, position)
      true -> :reset
    end
  end

  def next_check_in(%__MODULE__{started_at: started_at} = cinematic, now) when is_integer(started_at) do
    elapsed = now - started_at

    [end_at(cinematic) | for({timer, _position} <- cinematic.waypoints, timer > 0, do: timer)]
    |> Enum.filter(&(&1 >= elapsed))
    |> Enum.min(fn -> nil end)
    |> case do
      nil -> nil
      boundary -> boundary - elapsed + 1
    end
  end

  defp position(waypoints, elapsed) do
    passed = for {timer, position} <- waypoints, timer > 0 and timer < elapsed, do: {timer, position}

    case Enum.max_by(passed, &elem(&1, 0), fn -> nil end) do
      {_timer, position} -> position
      nil -> initial(waypoints)
    end
  end

  defp initial(waypoints) do
    case List.keyfind(waypoints, 0, 0) do
      {0, position} -> position
      nil -> nil
    end
  end

  defp view({start_x, start_y, _start_z}, {x, y, _z} = position) do
    if (start_x - x) ** 2 <= @in_line_squared or (start_y - y) ** 2 <= @in_line_squared,
      do: :reset,
      else: {:view, position}
  end

  defp end_at(%__MODULE__{waypoints: waypoints}),
    do: (waypoints |> Enum.map(&elem(&1, 0)) |> Enum.max(fn -> 0 end)) + @ends_after_ms
end
