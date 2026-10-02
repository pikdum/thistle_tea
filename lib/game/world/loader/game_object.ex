defmodule ThistleTea.Game.World.Loader.GameObject do
  @moduledoc """
  Loads the game-object spawns for a cell from Mangos and builds them into entity structs.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectSpawn
  alias ThistleTea.Game.Core.SpatialGrid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.SpawnPool
  alias ThistleTea.Game.World.System.SpawnPool.Catalog
  alias ThistleTea.Game.World.Transports

  def load({world, _x, _y} = cell) do
    events = GameEvent.get_events()

    world
    |> WorldRef.map_id()
    |> Mangos.GameObject.query_bounds(SpatialGrid.cell_bounds(cell), events)
    |> Mangos.Repo.all()
    |> Enum.each(&activate(&1, cell))
  end

  def blueprints(guids, events \\ GameEvent.get_events()) when is_list(guids) do
    Mangos.GameObject.query_guids(guids, events)
    |> Mangos.Repo.all()
    |> Map.new(fn game_object -> {{:game_object, game_object.guid}, build(game_object)} end)
  end

  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def preload_blueprints(guids, table \\ __MODULE__) when is_list(guids) do
    guids |> all_blueprints() |> Enum.each(fn {guid, blueprint} -> :ets.insert(table, {guid, blueprint}) end)
  end

  def cached_blueprint(guid, table \\ __MODULE__) when is_integer(guid) do
    case :ets.lookup(table, guid) do
      [{^guid, blueprint}] -> blueprint
      [] -> nil
    end
  end

  def all_blueprints(guids) when is_list(guids) do
    Mangos.GameObject.query_guids_all(guids)
    |> Mangos.Repo.all()
    |> Map.new(&{&1.guid, build(&1)})
  end

  def build(%Mangos.GameObject{game_object_template: %Mangos.GameObjectTemplate{} = template} = row) do
    template
    |> GameObjectTemplateLoader.build()
    |> GameObject.build(game_object_spawn(row))
  end

  def game_object_spawn(%Mangos.GameObject{} = row) do
    %GameObjectSpawn{
      guid: row.guid,
      entry: row.id,
      map_id: row.map,
      position: {row.position_x, row.position_y, row.position_z, row.orientation},
      rotation: {row.rotation0, row.rotation1, row.rotation2, row.rotation3},
      state: row.state,
      anim_progress: row.animprogress,
      respawn_seconds: row.spawntimesecsmin,
      event: event(row.game_event_game_object)
    }
  end

  def start_game_object(%GameObject{} = game_object), do: World.start_entity(game_object)
  def start_pool_game_object(%GameObject{} = game_object), do: World.start_incarnation(game_object)

  def spawned_by_default?(%Mangos.GameObject{spawntimesecsmin: seconds}) when is_integer(seconds) do
    seconds >= 0
  end

  def spawned_by_default?(%Mangos.GameObject{}), do: true

  defp event(%Mangos.GameEventGameObject{event: event}), do: event
  defp event(_row), do: nil

  defp activate(%Mangos.GameObject{spawntimesecsmin: seconds}, _cell) when is_integer(seconds) and seconds < 0, do: :ok

  defp activate(%Mangos.GameObject{} = game_object, cell) do
    blueprint = build(game_object)

    if not Transports.global_animation?(blueprint) do
      group = Catalog.group_for(:game_object, game_object.guid)
      blueprint = if match?({:singleton, _, _}, group), do: blueprint
      :ok = SpawnPool.activate(group, cell, blueprint)
    end
  end
end
