defmodule ThistleTea.Game.Entity.Data.CombatZone do
  @moduledoc "Pending activation and the next dungeon-wide combat pulse for one creature engagement."

  defstruct [:source_guid, :next_at]
end
