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

  def publish(%GameObject{} = entity, %Transport{} = route, pose) do
    snapshot = %{
      guid: entity.object.guid,
      entry: entity.object.entry,
      world: entity.internal.world,
      route_kind: route.kind,
      position: pose.position,
      progress_ms: pose.progress_ms,
      period_ms: route.period_ms
    }

    :ets.insert(__MODULE__, {entity.object.guid, snapshot})
    :ok
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
end
