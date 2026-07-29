defmodule ThistleTea.Game.World.Transports do
  @moduledoc """
  Runtime facade and read projection for moving transports.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Transport
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
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

  defp successful_start?(:ok), do: true
  defp successful_start?({:ok, _pid}), do: true
  defp successful_start?({:error, {:already_started, _pid}}), do: true
  defp successful_start?(_result), do: false
end
