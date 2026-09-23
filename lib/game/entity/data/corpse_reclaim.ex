defmodule ThistleTea.Game.Entity.Data.CorpseReclaim do
  @moduledoc "Retained repeat-death history and the current spirit-release timestamp."

  defstruct [:expires_at, :released_at]
end
