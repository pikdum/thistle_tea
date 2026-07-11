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

  def start_game_object(%GameObject{} = game_object), do: World.start_entity(game_object)
  def start_pool_game_object(%GameObject{} = game_object), do: World.start_incarnation(game_object)

  defp activate(%Mangos.GameObject{} = game_object, cell) do
    group = Catalog.group_for(:game_object, game_object.guid)
    blueprint = if match?({:singleton, _, _}, group), do: GameObject.build(game_object)
    SpawnPool.activate(group, cell, blueprint)
  end
end
