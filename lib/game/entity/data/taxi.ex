defmodule ThistleTea.Game.Entity.Data.Taxi.Node do
  @moduledoc false
  @enforce_keys [:id, :map_id, :position, :name, :mount_display_ids]
  defstruct [:id, :map_id, :position, :name, :mount_display_ids]
end

defmodule ThistleTea.Game.Entity.Data.Taxi.PathNode do
  @moduledoc false
  @enforce_keys [:index, :map_id, :position]
  defstruct [:index, :map_id, :position, flags: 0, delay_ms: 0]
end

defmodule ThistleTea.Game.Entity.Data.Taxi.Path do
  @moduledoc false
  @enforce_keys [:id, :source_node_id, :destination_node_id, :cost, :nodes]
  defstruct [:id, :source_node_id, :destination_node_id, :cost, :nodes]
end

defmodule ThistleTea.Game.Entity.Data.Taxi.Network do
  @moduledoc """
  Immutable flight network assembled at the database boundary.
  """
  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path

  @mask_words 8

  @enforce_keys [:nodes, :paths, :routes, :transitions, :network_node_ids]
  defstruct [:nodes, :paths, :routes, :transitions, :network_node_ids]

  def build(nodes, paths, transitions, spell_path_ids) when is_list(nodes) and is_list(paths) and is_map(transitions) do
    nodes = Map.new(nodes, &{&1.id, &1})
    paths = Map.new(paths, &{&1.id, &1})
    routes = Map.new(paths, fn {_id, path} -> {{path.source_node_id, path.destination_node_id}, path.id} end)
    spell_path_ids = MapSet.new(spell_path_ids)

    network_node_ids =
      nodes
      |> Map.keys()
      |> Enum.filter(&network_node?(&1, routes, spell_path_ids))
      |> MapSet.new()

    %__MODULE__{
      nodes: nodes,
      paths: paths,
      routes: routes,
      transitions: transitions,
      network_node_ids: network_node_ids
    }
  end

  def node(%__MODULE__{nodes: nodes}, id), do: Map.get(nodes, id)
  def path(%__MODULE__{paths: paths}, id), do: Map.get(paths, id)

  def route(%__MODULE__{} = network, source_node_id, destination_node_id) do
    with path_id when is_integer(path_id) <- Map.get(network.routes, {source_node_id, destination_node_id}) do
      path(network, path_id)
    end
  end

  def itinerary(%__MODULE__{} = network, node_ids) when is_list(node_ids) do
    with true <- length(node_ids) >= 2,
         {:ok, paths} <- itinerary_paths(network, node_ids) do
      {:ok, stitch_paths(paths, network.transitions)}
    else
      _invalid -> {:error, :no_such_path}
    end
  end

  def nearest_node(%__MODULE__{} = network, map_id, position, team) do
    network.network_node_ids
    |> Enum.flat_map(&nearest_candidate(node(network, &1), map_id, position, team))
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
    |> case do
      {%Node{} = node, _distance} -> node
      nil -> nil
    end
  end

  def mask(%__MODULE__{} = network, node_ids) do
    allowed = MapSet.intersection(MapSet.new(node_ids), network.network_node_ids)

    Enum.reduce(allowed, List.duplicate(0, @mask_words), fn node_id, words ->
      index = div(node_id - 1, 32)

      if index in 0..(@mask_words - 1) do
        List.update_at(words, index, &(&1 ||| 1 <<< rem(node_id - 1, 32)))
      else
        words
      end
    end)
  end

  defp network_node?(node_id, routes, spell_path_ids) do
    outgoing =
      for {{source, _destination}, path_id} <- routes,
          source == node_id,
          do: path_id

    outgoing == [] or Enum.any?(outgoing, &(not MapSet.member?(spell_path_ids, &1)))
  end

  defp nearest_candidate(
         %Node{map_id: map_id, position: node_position, mount_display_ids: mount_display_ids} = node,
         map_id,
         position,
         team
       ) do
    if Map.get(mount_display_ids, team, 0) > 0, do: [{node, distance_squared(position, node_position)}], else: []
  end

  defp nearest_candidate(_node, _map_id, _position, _team), do: []

  defp itinerary_paths(network, node_ids) do
    node_ids
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce_while({:ok, []}, fn [source, destination], {:ok, paths} ->
      case route(network, source, destination) do
        %Path{} = path -> {:cont, {:ok, paths ++ [path]}}
        nil -> {:halt, {:error, :no_such_path}}
      end
    end)
  end

  defp stitch_paths([%Path{} = path], _transitions) do
    %{paths: [path], nodes: path.nodes, total_cost: path.cost}
  end

  defp stitch_paths(paths, transitions) do
    [first | rest] = paths

    {nodes, _previous, total_cost} =
      Enum.reduce(rest, {first.nodes, first, first.cost}, fn path, {nodes, previous, cost} ->
        {in_node, out_node} =
          Map.get(
            transitions,
            {previous.id, path.id},
            {max(length(previous.nodes) - 2, 0), min(1, max(length(path.nodes) - 1, 0))}
          )

        kept_previous = Enum.take(nodes, length(nodes) - length(previous.nodes) + in_node + 1)
        next_nodes = Enum.drop(path.nodes, out_node)
        {kept_previous ++ next_nodes, path, cost + path.cost}
      end)

    %{paths: paths, nodes: nodes, total_cost: total_cost}
  end

  defp distance_squared({x, y, z}, {nx, ny, nz}) do
    (nx - x) * (nx - x) + (ny - y) * (ny - y) + (nz - z) * (nz - z)
  end
end
