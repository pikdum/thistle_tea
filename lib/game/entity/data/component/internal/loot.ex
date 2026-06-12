defmodule ThistleTea.Game.Entity.Data.Component.Internal.Loot do
  @moduledoc """
  A mob's loot and corpse-phase state: the loot template and gold range (or a
  fixed override), tap ownership, and the live loot session with its corpse
  decay token.
  """
  defstruct [
    :id,
    :min_gold,
    :max_gold,
    :override,
    :session,
    :tapped_by,
    :corpse_token,
    corpse_removed?: false
  ]
end
