defmodule ThistleTea.Game.Entity.Data.Component.Internal.Corpse do
  @moduledoc "Retained body identity and battleground loot, independent of the owner's connection."

  defstruct [:level, :team, :session, :looter_guid, faction_metadata: %{}]
end
