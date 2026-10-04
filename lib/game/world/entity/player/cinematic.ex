defmodule ThistleTea.Game.World.Entity.Player.Cinematic do
  @moduledoc """
  Follows a first login's intro cinematic camera (`Core.Player.Cinematic`)
  through the player's visibility, waking only when the camera reaches its
  next waypoint, until the client reports the cinematic over.
  """

  alias ThistleTea.Game.Core.Player.Cinematic
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Loader.CinematicWaypoint, as: CinematicWaypointLoader
  alias ThistleTea.Game.World.Visibility

  def prepare(state, nil), do: state

  def prepare(%{character: character} = state, sequence_id) do
    case CinematicWaypointLoader.get(sequence_id) do
      [] -> state
      waypoints -> %{state | cinematic: Cinematic.prepare(sequence_id, waypoints, character.movement_block.position)}
    end
  end

  def begin(%{cinematic: %Cinematic{} = cinematic} = state),
    do: update(%{state | cinematic: Cinematic.begin(cinematic, Time.now())})

  def begin(state), do: state

  def update(%{cinematic: %Cinematic{started_at: started_at} = cinematic} = state) when is_integer(started_at) do
    now = Time.now()

    case Cinematic.camera(cinematic, now) do
      :finished -> finish(state)
      :reset -> state |> Visibility.reset_camera() |> schedule(now)
      {:view, position} -> state |> Visibility.set_camera(position) |> schedule(now)
    end
  end

  def update(state), do: state

  def finish(%{cinematic: %Cinematic{}} = state), do: %{Visibility.reset_camera(state) | cinematic: nil}
  def finish(state), do: state

  defp schedule(%{cinematic: cinematic} = state, now) do
    if delay = Cinematic.next_check_in(cinematic, now), do: Process.send_after(self(), :cinematic_camera, delay)
    state
  end
end
