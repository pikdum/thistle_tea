defmodule ThistleTea.Game.World.Terrain do
  @moduledoc "Boot-loaded terrain liquid data; runtime queries sample immutable tiles from ETS."

  alias ThistleTea.Game.Core.Terrain.Tile
  alias ThistleTea.Game.World.Loader.Exploration

  require Logger

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _existing -> table
    end
  end

  def load(directory, table \\ __MODULE__) do
    files = Path.wildcard(Path.join(directory, "*.map"))
    results = Enum.frequencies_by(files, &load_tile(&1, table))

    if files == [] do
      Logger.warning("Terrain liquid data unavailable in #{directory}; generate it with nix run .#terrain-data")
    else
      Logger.info("Terrain liquid tiles: #{inspect(results)}")
    end

    results
  end

  def liquid(map_id, {x, y, _z} = position, table \\ __MODULE__) do
    {row, column} = Tile.coordinates(x, y)

    case :ets.lookup(table, {map_id, row, column}) do
      [{_key, %Tile{} = tile}] -> Tile.sample(tile, position)
      [] -> nil
    end
  end

  def zone_and_area(map_id, {x, y, _z} = position, table \\ __MODULE__) do
    {row, column} = Tile.coordinates(x, y)

    with [{_key, %Tile{} = tile}] <- :ets.lookup(table, {map_id, row, column}),
         bit when is_integer(bit) <- Tile.area_bit(tile, position),
         %{id: id, map: ^map_id, parent_area_table: parent} <- Exploration.area_by_bit(map_id, bit) do
      {if(is_integer(parent) and parent > 0, do: parent, else: id), id}
    else
      _missing -> nil
    end
  end

  defp load_tile(path, table) do
    with [_, map, row, column] <- Regex.run(~r/^(\d{4})(\d{2})(\d{2})\.map$/, Path.basename(path)),
         {:ok, binary} <- File.read(path),
         {:ok, tile} <- Tile.decode(binary) do
      if tile do
        key = {String.to_integer(map), String.to_integer(row), String.to_integer(column)}
        :ets.insert(table, {key, tile})
        :loaded
      else
        :dry
      end
    else
      _invalid ->
        Logger.warning("Invalid terrain liquid tile: #{path}")
        :invalid
    end
  end
end
