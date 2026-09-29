defmodule ThistleTea.Game.Core.Travel.Taxi.Node do
  @moduledoc false
  @enforce_keys [:id, :map_id, :position, :name, :mount_display_ids]
  defstruct [:id, :map_id, :position, :name, :mount_display_ids]
end

defmodule ThistleTea.Game.Core.Travel.Taxi.PathNode do
  @moduledoc false
  @enforce_keys [:index, :map_id, :position]
  defstruct [:index, :map_id, :position, flags: 0, delay_ms: 0]
end

defmodule ThistleTea.Game.Core.Travel.Taxi.Path do
  @moduledoc false
  @enforce_keys [:id, :source_node_id, :destination_node_id, :cost, :nodes]
  defstruct [:id, :source_node_id, :destination_node_id, :cost, :nodes]
end

defmodule ThistleTea.Game.Core.Travel.Taxi.Flight do
  @moduledoc false
  @enforce_keys [
    :token,
    :path_ids,
    :source_node_id,
    :destination_node_id,
    :destination_position,
    :mount_display_id,
    :started_at,
    :duration_ms
  ]
  defstruct [
    :token,
    :path_ids,
    :source_node_id,
    :destination_node_id,
    :destination_position,
    :mount_display_id,
    :started_at,
    :duration_ms,
    :remaining_nodes
  ]
end

defmodule ThistleTea.Game.Core.Travel.Taxi.Network do
  @moduledoc """
  Immutable flight network assembled at the database boundary.
  """
  import Bitwise, only: [&&&: 2, <<<: 2, |||: 2]

  alias ThistleTea.Game.Core.Travel.Taxi.Node
  alias ThistleTea.Game.Core.Travel.Taxi.Path

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

  def node_ids_from_mask(words) when is_list(words) do
    words
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {word, word_index}, node_ids ->
      Enum.reduce(0..31, node_ids, &put_mask_bit(&2, word, word_index, &1))
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

  defp put_mask_bit(node_ids, word, word_index, bit) do
    if (word &&& 1 <<< bit) == 0 do
      node_ids
    else
      MapSet.put(node_ids, word_index * 32 + bit + 1)
    end
  end

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

defmodule ThistleTea.Game.Core.Travel.Taxi do
  @moduledoc """
  Pure character transitions for starting, suspending, resuming, and finishing taxi flights.
  """
  import Bitwise, only: [&&&: 2, bnot: 1, |||: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.ExtraAttacks
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Movement.Falling
  alias ThistleTea.Game.Core.Spell.Mount
  alias ThistleTea.Game.Core.Travel.Taxi.Flight
  alias ThistleTea.Game.Core.Travel.Taxi.Node

  @remove_client_control_flag 0x00000004
  @taxi_flight_flag 0x00100000
  @taxi_flags @remove_client_control_flag ||| @taxi_flight_flag
  @flight_speed 32.0

  def start(
        %Character{unit: %Unit{}, internal: %Internal{}} = character,
        itinerary,
        %Node{} = destination,
        mount_display_id,
        token,
        now
      )
      when is_map(itinerary) and is_integer(mount_display_id) and mount_display_id >= 0 and is_reference(token) and
             is_integer(now) do
    character = character |> prepare_auras(now) |> Mount.dismount(now) |> ExtraAttacks.clear() |> Falling.reset()
    unit = character.unit
    positions = Enum.map(itinerary.nodes, & &1.position)
    path_ids = Enum.map(itinerary.paths, & &1.id)
    source_node_id = hd(itinerary.paths).source_node_id
    destination_node_id = destination.id

    character =
      %{
        character
        | unit: %{unit | flags: (unit.flags || 0) ||| @taxi_flags, mount_display_id: mount_display_id},
          player: %{character.player | coinage: character.player.coinage - itinerary.total_cost}
      }
      |> Movement.move_along_path(positions, [velocity: @flight_speed, flying?: true, run?: true], now)

    flight = %Flight{
      token: token,
      path_ids: path_ids,
      source_node_id: source_node_id,
      destination_node_id: destination_node_id,
      destination_position: List.last(positions),
      mount_display_id: mount_display_id,
      started_at: now,
      duration_ms: character.movement_block.duration
    }

    character = %{character | internal: %{character.internal | taxi_flight: flight}}
    {character, effects} = Effects.drain(character)
    {Entity.mark_broadcast_update(character), effects}
  end

  def finish(
        %Character{
          unit: %Unit{} = unit,
          internal: %Internal{taxi_flight: %Flight{destination_position: {x, y, z}}},
          movement_block: %MovementBlock{}
        } = character,
        now
      )
      when is_integer(now) do
    character = Movement.finish(character, now)
    {_old_x, _old_y, _old_z, orientation} = character.movement_block.position
    movement_block = %{character.movement_block | position: {x, y, z, orientation}}
    unit = %{unit | flags: (unit.flags || 0) &&& bnot(@taxi_flags), mount_display_id: 0}
    internal = %{character.internal | taxi_flight: nil}

    %{character | unit: unit, internal: internal, movement_block: movement_block}
    |> Falling.reset()
    |> Entity.mark_broadcast_update()
  end

  def finish(%Character{} = character, _now), do: character

  def pause(%Character{internal: %Internal{taxi_flight: %Flight{remaining_nodes: [_ | _]}}} = character, _now),
    do: character

  def pause(%Character{internal: %Internal{taxi_flight: %Flight{} = flight}} = character, now) do
    case Movement.resume_spline(character, now) do
      %Character{movement_block: movement} ->
        character = Movement.finish(character, now)

        flight = %{
          flight
          | token: nil,
            started_at: nil,
            duration_ms: movement.duration,
            remaining_nodes: movement.spline_nodes
        }

        %{character | internal: %{character.internal | taxi_flight: flight}}

      nil ->
        if is_integer(character.internal.movement_start_time), do: finish(character, now), else: cancel(character, now)
    end
  end

  def pause(%Character{} = character, _now), do: character

  def resume(
        %Character{internal: %Internal{taxi_flight: %Flight{remaining_nodes: [_ | _] = nodes} = flight}} = character,
        token,
        now
      )
      when is_reference(token) and is_integer(now) do
    if Death.alive?(character) do
      opts = [flying?: true, run?: true]
      character = Movement.start_timed_path(character, nodes, flight.duration_ms, now, opts)
      resume_started_path(character, flight, token, now, opts)
    else
      {cancel(character, now), []}
    end
  end

  def resume(%Character{} = character, _token, _now), do: {character, []}

  defp resume_started_path(
         %Character{internal: %Internal{movement_start_time: nil}} = character,
         _flight,
         _token,
         now,
         _opts
       ), do: {finish(character, now), []}

  defp resume_started_path(%Character{} = character, %Flight{} = flight, token, now, opts) do
    flight = %{flight | token: token, started_at: now, remaining_nodes: nil}

    unit = %{
      character.unit
      | flags: (character.unit.flags || 0) ||| @taxi_flags,
        mount_display_id: flight.mount_display_id
    }

    character = %{character | unit: unit, internal: %{character.internal | taxi_flight: flight}}
    {Entity.mark_broadcast_update(character), [Effects.monster_move(opts)]}
  end

  def cancel(%Character{internal: %Internal{taxi_flight: %Flight{}}} = character, now) do
    character = Movement.finish(character, now)
    unit = %{character.unit | flags: (character.unit.flags || 0) &&& bnot(@taxi_flags), mount_display_id: 0}
    internal = %{character.internal | taxi_flight: nil}

    %{character | unit: unit, internal: internal} |> Falling.reset() |> Entity.mark_broadcast_update()
  end

  def cancel(%Character{} = character, _now), do: character

  def active?(%Character{internal: %Internal{taxi_flight: %Flight{}}}), do: true
  def active?(%Character{}), do: false

  def disallowed_form?(%Character{unit: %Unit{shapeshift_form: form}}), do: form not in [nil, 0, 17, 18, 19, 28, 30]

  defp prepare_auras(character, now) do
    types = if disallowed_form?(character), do: [:mod_stealth, :mod_shapeshift, :transform], else: [:mod_stealth]
    {character, effects} = Aura.remove_aura_types(character, types, now)
    Effects.enqueue(character, effects)
  end
end
