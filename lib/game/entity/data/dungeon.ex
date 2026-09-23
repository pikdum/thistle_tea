defmodule ThistleTea.Game.Entity.Data.Dungeon do
  @moduledoc "Dungeon map identity, parent linkage, and the outdoor entrance shown to ghosts."

  defstruct [:map_id, :name, :parent_map, :zone_id, :ghost_entrance]
end
