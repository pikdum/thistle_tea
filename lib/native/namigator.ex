defmodule ThistleTea.Native.Namigator do
  @moduledoc """
  Fine NIF bindings to namigator for runtime pathfinding queries.
  """

  require Logger

  @on_load :load_nif

  @maps_key {__MODULE__, :maps}

  @maps_to_process [
    {0, "Azeroth"},
    {1, "Kalimdor"},
    {451, "development"},
    {389, "OrgrimmarInstance"},
    {329, "Stratholme"}
  ]

  def load_nif do
    path = :filename.join(:code.priv_dir(:thistle_tea), ~c"native/namigator_ex")
    :erlang.load_nif(path, 0)
  end

  def load(out_dir) when is_binary(out_dir) do
    {maps, failures} = load_maps(out_dir)
    :persistent_term.put(@maps_key, maps)

    case failures do
      [] ->
        Logger.info("Loaded #{map_size(maps)} navigation maps.")

      _ ->
        Logger.warning(
          "Loaded #{map_size(maps)}/#{length(@maps_to_process)} navigation maps; " <>
            "failed: #{inspect(Enum.reverse(failures))}"
        )
    end

    failures == []
  end

  def get_zone_and_area(map_id, x, y, z) do
    with_map(map_id, &get_zone_and_area_native(&1, x, y, z))
  end

  def find_random_point_around_circle(map_id, x, y, z, radius) do
    with_map(map_id, &find_random_point_around_circle_native(&1, x, y, z, radius))
  end

  def load_all_adts(map_id) do
    with_map(map_id, &load_all_adts_native/1)
  end

  def load_adt_at(map_id, x, y) do
    with_map(map_id, &load_adt_at_native(&1, x, y))
  end

  def load_adt(map_id, x, y) do
    with_map(map_id, &load_adt_native(&1, x, y))
  end

  def unload_adt(map_id, x, y) do
    with_map(map_id, &unload_adt_native(&1, x, y))
  end

  def find_path(map_id, start_x, start_y, start_z, stop_x, stop_y, stop_z) do
    with_map(map_id, &find_path_native(&1, start_x, start_y, start_z, stop_x, stop_y, stop_z))
  end

  def find_point_between_points(map_id, start_x, start_y, start_z, stop_x, stop_y, stop_z, distance) do
    with_map(
      map_id,
      &find_point_between_points_native(&1, start_x, start_y, start_z, stop_x, stop_y, stop_z, distance)
    )
  end

  def find_heights(map_id, x, y) do
    with_map(map_id, &find_heights_native(&1, x, y))
  end

  def line_of_sight(map_id, start_x, start_y, start_z, stop_x, stop_y, stop_z) do
    with_map(map_id, &line_of_sight_native(&1, start_x, start_y, start_z, stop_x, stop_y, stop_z))
  end

  defp load_maps(out_dir) do
    Enum.reduce(@maps_to_process, {%{}, []}, fn {map_id, map_name}, {maps, failures} ->
      case load_map_native(out_dir, map_name) do
        {:ok, map} -> {Map.put(maps, map_id, map), failures}
        {:error, code} -> {maps, [{map_name, code} | failures]}
      end
    end)
  end

  defp with_map(map_id, callback) do
    case Map.fetch(:persistent_term.get(@maps_key, %{}), map_id) do
      {:ok, map} -> callback.(map)
      :error -> nil
    end
  end

  defp load_map_native(_out_dir, _map_name), do: :erlang.nif_error(:nif_not_loaded)
  defp get_zone_and_area_native(_map, _x, _y, _z), do: :erlang.nif_error(:nif_not_loaded)

  defp find_random_point_around_circle_native(_map, _x, _y, _z, _radius), do: :erlang.nif_error(:nif_not_loaded)

  defp load_all_adts_native(_map), do: :erlang.nif_error(:nif_not_loaded)
  defp load_adt_native(_map, _x, _y), do: :erlang.nif_error(:nif_not_loaded)
  defp load_adt_at_native(_map, _x, _y), do: :erlang.nif_error(:nif_not_loaded)
  defp unload_adt_native(_map, _x, _y), do: :erlang.nif_error(:nif_not_loaded)

  defp find_path_native(_map, _start_x, _start_y, _start_z, _stop_x, _stop_y, _stop_z),
    do: :erlang.nif_error(:nif_not_loaded)

  defp find_point_between_points_native(_map, _start_x, _start_y, _start_z, _stop_x, _stop_y, _stop_z, _distance),
    do: :erlang.nif_error(:nif_not_loaded)

  defp find_heights_native(_map, _x, _y), do: :erlang.nif_error(:nif_not_loaded)

  defp line_of_sight_native(_map, _start_x, _start_y, _start_z, _stop_x, _stop_y, _stop_z),
    do: :erlang.nif_error(:nif_not_loaded)
end
