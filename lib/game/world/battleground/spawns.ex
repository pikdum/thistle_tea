defmodule ThistleTea.Game.World.Battleground.Spawns do
  @moduledoc "Match-owned event selection and spawn eligibility shared by activation, respawn, and node changes."

  alias ThistleTea.Game.Battleground.Rules
  alias ThistleTea.Game.World.Loader.Battleground, as: Catalog
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.WorldRef

  def init do
    case :ets.whereis(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])
      table -> table
    end
  end

  def open(%WorldRef{} = world) do
    :ets.insert(__MODULE__, {world, Rules.initial_events(world.map_id)})
    :ok
  end

  def close(%WorldRef{} = world), do: :ets.delete(__MODULE__, world)

  def stop_respawns(%WorldRef{} = world, event) do
    select_event(world, event, nil)
  end

  def allowed?(%WorldRef{map_id: map_id} = world, {kind, db_guid}, catalog \\ Catalog) do
    case catalog.bindings(map_id, kind, db_guid) do
      [] -> true
      bindings -> Enum.any?(bindings, &(Map.get(events(world), &1.event1) == &1.event2))
    end
  end

  def set_event(%WorldRef{} = world, event, state, catalog \\ Catalog, pool \\ SpawnPool) do
    select_event(world, event, state)

    world.map_id
    |> catalog.event_members(event)
    |> Enum.uniq_by(&{&1.kind, &1.db_guid})
    |> Enum.each(fn member ->
      key = {member.kind, member.db_guid}

      if allowed?(world, key, catalog),
        do: pool.resume(world, key),
        else: pool.suspend_spawn(world, key)
    end)

    :ok
  end

  defp select_event(world, event, state) do
    :ets.insert(__MODULE__, {world, Map.put(events(world), event, state)})
    :ok
  end

  defp events(world) do
    case :ets.lookup(__MODULE__, world) do
      [{^world, events}] -> events
      [] -> %{}
    end
  end
end
