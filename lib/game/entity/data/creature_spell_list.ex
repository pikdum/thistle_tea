defmodule ThistleTea.Game.Entity.Data.CreatureSpellList do
  @moduledoc "A preloaded creature spell list selected by templates or runtime scripts."

  @enforce_keys [:id]
  defstruct [:id, spells: []]
end
