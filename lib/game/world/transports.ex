defmodule ThistleTea.Game.World.Transports do
  @moduledoc """
  Runtime facade and read projection for moving transports.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Transport
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.MapTemplate, as: MapTemplateLoader
  alias ThistleTea.Game.World.Loader.Transport, as: TransportLoader
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def start_all do
    ship_results =
      Enum.map(TransportLoader.ship_entries(), fn entry ->
        with %Transport{} = route <- TransportLoader.get(entry),
             template when not is_nil(template) <- GameObjectTemplateLoader.get(entry) do
          pose = TransportLogic.pose_at(route, 0)

          template
          |> GameObject.build_transport(pose)
          |> World.start_entity()
        else
          _ -> {:error, {:missing_transport_definition, entry}}
        end
      end)

    animation_results =
      TransportLoader.animation_spawns()
      |> Enum.filter(&global_animation?/1)
      |> Enum.map(&World.start_entity/1)

    errors = Enum.reject(ship_results ++ animation_results, &successful_start?/1)
    if errors == [], do: :ok, else: {:error, errors}
  end

  def global_animation?(%GameObject{game_object: %{type_id: 11}, internal: %{world: %{map_id: map_id}}}) do
    not MapTemplateLoader.dungeon?(map_id) and not MapTemplateLoader.battleground?(map_id)
  end

  def global_animation?(%GameObject{}), do: false

  def publish(%GameObject{} = entity, %Transport{} = route, pose, passenger_count \\ 0) do
    snapshot = %{
      guid: entity.object.guid,
      entry: entity.object.entry,
      world: entity.internal.world,
      name: route.name,
      route_kind: route.kind,
      position: pose.position,
      progress_ms: pose.progress_ms,
      period_ms: route.period_ms,
      frame_index: pose.frame_index,
      moving?: pose.moving?,
      passenger_count: passenger_count
    }

    :ets.insert(__MODULE__, {entity.object.guid, snapshot})
    :ok
  end

  def all do
    __MODULE__
    |> :ets.tab2list()
    |> Enum.map(fn {_guid, snapshot} -> snapshot end)
  rescue
    ArgumentError -> []
  end

  def on_world(%WorldRef{} = world) do
    all()
    |> Enum.filter(&(&1.world == world))
    |> Enum.sort_by(& &1.guid)
  end

  def ships_on_world(%WorldRef{} = world) do
    world
    |> on_world()
    |> Enum.filter(&(&1.route_kind == :ship))
  end

  def ship?(guid) when is_integer(guid) do
    match?(%{route_kind: :ship}, get(guid))
  end

  def ship?(_guid), do: false

  def target(character, entry \\ nil)

  def target(%Character{} = character, entry) when is_integer(entry) do
    candidates = Enum.filter(all(), &(&1.entry == entry))
    nearest_or_first(character, candidates)
  end

  def target(%Character{movement_block: %MovementBlock{transport_guid: guid}} = character, nil) when is_integer(guid) do
    get(guid) || nearest(character, on_world(character.internal.world))
  end

  def target(%Character{} = character, nil) do
    nearest(character, on_world(character.internal.world))
  end

  def unpublish(guid) when is_integer(guid) do
    :ets.delete(__MODULE__, guid)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def get(guid) when is_integer(guid) do
    case :ets.lookup(__MODULE__, guid) do
      [{^guid, snapshot}] -> snapshot
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def advance(guid, milliseconds) when is_integer(guid) and is_integer(milliseconds) do
    Entity.call(guid, {:advance, milliseconds})
  end

  def reconcile(
        %Character{movement_block: %MovementBlock{transport_guid: nil}},
        %MovementBlock{transport_guid: nil} = movement_block
      ) do
    {:ok, movement_block}
  end

  def reconcile(
        %Character{object: %{guid: player_guid}, movement_block: %MovementBlock{transport_guid: previous_guid}},
        %MovementBlock{transport_guid: nil} = movement_block
      ) do
    leave(previous_guid, player_guid)
    {:ok, movement_block}
  end

  def reconcile(
        %Character{
          object: %{guid: player_guid},
          internal: %{world: world},
          movement_block: %MovementBlock{transport_guid: previous_guid}
        },
        %MovementBlock{transport_guid: transport_guid, transport_position: local_position} = movement_block
      )
      when is_integer(transport_guid) do
    with true <- Guid.transport?(transport_guid),
         true <- TransportLogic.valid_passenger_position?(local_position),
         {:ok, transport} <- Entity.board_transport(transport_guid, player_guid, world, local_position) do
      leave_changed(previous_guid, transport_guid, player_guid)
      position = TransportLogic.passenger_world_position(local_position, transport.position)
      {:ok, %{movement_block | position: position}}
    else
      _ -> {:error, :invalid_transport}
    end
  end

  def reconcile(%Character{}, %MovementBlock{}), do: {:error, :invalid_transport}

  def leave(%Character{object: %{guid: player_guid}, movement_block: %MovementBlock{transport_guid: transport_guid}}) do
    leave(transport_guid, player_guid)
  end

  def leave(_character), do: :ok

  defp successful_start?(:ok), do: true
  defp successful_start?({:ok, _pid}), do: true
  defp successful_start?({:error, {:already_started, _pid}}), do: true
  defp successful_start?(_result), do: false

  defp leave_changed(previous_guid, current_guid, player_guid) when previous_guid != current_guid do
    leave(previous_guid, player_guid)
  end

  defp leave_changed(_previous_guid, _current_guid, _player_guid), do: :ok

  defp leave(transport_guid, player_guid) when is_integer(transport_guid) do
    Entity.leave_transport(transport_guid, player_guid)
    :ok
  end

  defp leave(_transport_guid, _player_guid), do: :ok

  defp nearest_or_first(%Character{} = character, candidates) do
    same_world = Enum.filter(candidates, &(&1.world == character.internal.world))
    nearest(character, same_world) || Enum.min_by(candidates, & &1.guid, fn -> nil end)
  end

  defp nearest(%Character{movement_block: %MovementBlock{position: {x, y, z, _orientation}}}, candidates) do
    Enum.min_by(
      candidates,
      fn %{position: {transport_x, transport_y, transport_z, _orientation}} ->
        SpatialHash.distance({x, y, z}, {transport_x, transport_y, transport_z})
      end,
      fn -> nil end
    )
  end
end
