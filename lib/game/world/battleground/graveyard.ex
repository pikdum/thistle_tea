defmodule ThistleTea.Game.World.Battleground.Graveyard do
  @moduledoc "Resolves a participant's current position into the match's authoritative graveyard rules."

  alias ThistleTea.Game.Battleground.Rules
  alias ThistleTea.Game.World

  def for_player(match, guid) do
    case Map.get(match.players, guid) do
      %{team: team} -> Rules.fetch!(match.world.map_id).graveyard(match, team, position(match.world, guid))
      nil -> nil
    end
  end

  defp position(world, guid) do
    case World.position(guid) do
      {^world, x, y, z} -> {x, y, z}
      _missing -> nil
    end
  end
end
