defmodule ThistleTea.Game.World.Graveyards do
  @moduledoc "Runtime faction control layered over the boot-loaded graveyard links."

  alias ThistleTea.Game.World.Loader.Graveyard

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      existing -> existing
    end
  end

  def control(id, faction, table \\ __MODULE__) when faction in [nil, 469, 67] do
    :ets.insert(table, {id, faction})
    :ok
  end

  def project(graveyards, table \\ __MODULE__) do
    Enum.flat_map(graveyards, fn graveyard ->
      case :ets.lookup(table, graveyard.id) do
        [{_id, nil}] -> []
        [{_id, faction}] -> [%{graveyard | faction: faction}]
        [] -> [graveyard]
      end
    end)
  end

  def closest(map, position, team) do
    Graveyard.closest(map, position, team, fn area -> area |> Graveyard.for_area() |> project() end)
  end
end
