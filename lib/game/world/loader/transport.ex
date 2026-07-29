defmodule ThistleTea.Game.World.Loader.Transport do
  @moduledoc """
  Loads transport definitions from VMangos and DBC data into an ETS catalog.
  """

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Transport
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic

  @client_build 5875
  @client_patch 10
  @ship_type 15
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    specs = ship_specs()
    ship_routes = load_ship_routes(specs)
    animation_routes = load_animation_routes()

    Enum.each(ship_routes ++ animation_routes, &cache/1)
    :ets.insert(__MODULE__, {:ship_entries, Enum.map(ship_routes, & &1.entry)})

    :ok
  end

  def ship_specs do
    periods =
      Mangos.TransportSchedule
      |> where([schedule], schedule.build <= @client_build)
      |> Mangos.Repo.all()
      |> Enum.group_by(& &1.entry)
      |> Map.new(fn {entry, rows} -> {entry, Enum.max_by(rows, & &1.build)} end)

    Mangos.GameObjectTemplate
    |> where([template], template.type == @ship_type and template.patch <= @client_patch)
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry)
    |> Enum.map(fn {_entry, rows} -> Enum.max_by(rows, & &1.patch) end)
    |> Enum.map(fn template ->
      schedule = Map.get(periods, template.entry)

      %{
        entry: template.entry,
        name: schedule_name(schedule, template.name),
        path_id: template.data0,
        move_speed: template.data1,
        accel_rate: template.data2,
        period_ms: schedule_period(schedule)
      }
    end)
    |> Enum.sort_by(& &1.entry)
  end

  def load_ship_routes(specs) when is_list(specs) do
    nodes_by_path = specs |> Enum.map(& &1.path_id) |> load_taxi_path_nodes()

    Enum.map(specs, fn spec ->
      TransportLogic.build_ship(
        spec.entry,
        spec.name,
        spec.path_id,
        Map.fetch!(nodes_by_path, spec.path_id),
        spec.move_speed,
        spec.accel_rate,
        spec.period_ms
      )
    end)
  end

  def load_taxi_path_nodes(path_ids) when is_list(path_ids) do
    TaxiPathNode
    |> where([node], node.taxi_path in ^path_ids)
    |> order_by([node], [node.taxi_path, node.node_index])
    |> DBC.all()
    |> Enum.group_by(
      & &1.taxi_path,
      &%{
        node_index: &1.node_index,
        map_id: &1.map,
        position: {&1.location_x, &1.location_y, &1.location_z},
        flags: &1.flags,
        delay: &1.delay
      }
    )
  end

  def load_animation_routes(entries \\ :all)

  def load_animation_routes(:all) do
    TransportAnimation
    |> order_by([frame], [frame.transport, frame.time_index])
    |> DBC.all()
    |> build_animation_routes()
  end

  def load_animation_routes(entries) when is_list(entries) do
    TransportAnimation
    |> where([frame], frame.transport in ^entries)
    |> order_by([frame], [frame.transport, frame.time_index])
    |> DBC.all()
    |> build_animation_routes()
  end

  def get(entry) when is_integer(entry) do
    case :ets.lookup(__MODULE__, {:route, entry}) do
      [{{:route, ^entry}, %Transport{} = route}] -> route
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def ship_entries do
    case :ets.lookup(__MODULE__, :ship_entries) do
      [{:ship_entries, entries}] -> entries
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  defp build_animation_routes(rows) do
    rows
    |> Enum.group_by(& &1.transport)
    |> Enum.map(fn {entry, frames} ->
      frames =
        Enum.map(frames, fn frame ->
          %{
            time_ms: frame.time_index,
            position: {frame.location_x, frame.location_y, frame.location_z},
            sequence: frame.sequence
          }
        end)

      TransportLogic.build_animation(entry, "Transport #{entry}", frames)
    end)
    |> Enum.sort_by(& &1.entry)
  end

  defp cache(%Transport{} = route) do
    :ets.insert(__MODULE__, {{:route, route.entry}, route})
    route
  end

  defp schedule_name(nil, fallback), do: fallback
  defp schedule_name(%{name: name}, _fallback) when is_binary(name) and name != "", do: name
  defp schedule_name(_schedule, fallback), do: fallback

  defp schedule_period(nil), do: 0
  defp schedule_period(%{period: period}), do: period
end
