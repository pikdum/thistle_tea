defmodule ThistleTea.Game.Entity.Data.Talent do
  @moduledoc false
  defstruct [
    :id,
    :tab_id,
    :tier,
    :column,
    :depends_on,
    :depends_on_rank,
    :required_spell_id,
    rank_spell_ids: []
  ]
end
