defmodule ThistleTea.Game.World.Loader.GameObject do
  @moduledoc """
  Loads the game-object spawns for a cell from Mangos into entity structs.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.SpawnPool.Catalog
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.Transports

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.GameObject.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.each(&activate(&1, cell))
  end

  def blueprints(guids, events \\ GameEvent.get_events()) when is_list(guids) do
    Mangos.GameObject.query_guids(guids, events)
    |> Mangos.Repo.all()
    |> Map.new(fn game_object -> {{:game_object, game_object.guid}, GameObject.build(game_object)} end)
  end

  def all_blueprints(guids) when is_list(guids) do
    Mangos.GameObject.query_guids_all(guids)
    |> Mangos.Repo.all()
    |> Map.new(&{&1.guid, GameObject.build(&1)})
  end

  def start_game_object(%GameObject{} = game_object), do: World.start_entity(game_object)
  def start_pool_game_object(%GameObject{} = game_object), do: World.start_incarnation(game_object)

  def spawned_by_default?(%Mangos.GameObject{spawntimesecsmin: seconds}) when is_integer(seconds) do
    seconds >= 0
  end

  def spawned_by_default?(%Mangos.GameObject{}), do: true

  defp activate(%Mangos.GameObject{spawntimesecsmin: seconds}, _cell) when is_integer(seconds) and seconds < 0, do: :ok

  defp activate(%Mangos.GameObject{} = game_object, cell) do
    blueprint = GameObject.build(game_object)

    if not Transports.global_animation?(blueprint) do
      group = Catalog.group_for(:game_object, game_object.guid)
      blueprint = if match?({:singleton, _, _}, group), do: blueprint
      :ok = SpawnPool.activate(group, cell, blueprint)
    end
  end
end
