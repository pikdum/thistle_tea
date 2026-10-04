defmodule ThistleTea.Game.World.Loader.CinematicWaypoint do
  @moduledoc """
  Boot-loaded vmangos `cinematic_waypoints`: where an intro cinematic's camera
  is at each point in its run, keyed by cinematic sequence, as
  `{timer_ms, {x, y, z}}`.
  """

  alias ThistleTea.DB.Mangos

  @key {__MODULE__, :waypoints}

  def load_all do
    waypoints =
      Mangos.CinematicWaypoint
      |> Mangos.Repo.all()
      |> Enum.group_by(& &1.cinematic, &{&1.timer, {&1.position_x, &1.position_y, &1.position_z}})
      |> Map.new(fn {cinematic, points} -> {cinematic, Enum.sort(points)} end)

    :persistent_term.put(@key, waypoints)
    :ok
  end

  def get(sequence_id), do: Map.get(:persistent_term.get(@key, %{}), sequence_id, [])
end
