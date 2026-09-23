defmodule ThistleTea.Game.Entity.Logic.CorpseTravel do
  @moduledoc "Pure dungeon ancestry and corpse-marker routing for spirit runs."

  alias ThistleTea.Game.Entity.Data.Dungeon

  def destination(corpse_map, target_map, dungeons) do
    if linked?(corpse_map, target_map, dungeons, MapSet.new()), do: {:ok, corpse_map}, else: {:error, :wrong_dungeon}
  end

  def entrance(corpse_map, player_map, dungeons) when corpse_map != player_map do
    case Map.get(dungeons, corpse_map) do
      %Dungeon{ghost_entrance: entrance} -> entrance
      _missing -> nil
    end
  end

  def entrance(_corpse_map, _player_map, _dungeons), do: nil

  defp linked?(map, target, dungeons, visited) do
    case Map.get(dungeons, map) do
      %Dungeon{map_id: ^target} ->
        true

      %Dungeon{parent_map: parent} when is_integer(parent) and parent > 0 ->
        not MapSet.member?(visited, map) and linked?(parent, target, dungeons, MapSet.put(visited, map))

      _missing ->
        false
    end
  end
end
