defmodule ThistleTea.Game.Core.Player.TalentCatalog do
  @moduledoc """
  Read contract for the static talent trees. `Core.Player.Talents` takes an
  implementing module as an argument, so callers choose the data source
  (the boot-loaded `World.Loader.Talent` cache in the game, a stub in tests).
  """
  alias ThistleTea.Game.Core.Player.Talent

  @callback get(talent_id :: integer()) :: %Talent{} | nil
  @callback tab_ids(class :: integer()) :: [integer()]
  @callback by_spell(spell_id :: integer()) ::
              {talent_id :: integer(), tab_id :: integer(), rank_index :: integer()} | nil
end
