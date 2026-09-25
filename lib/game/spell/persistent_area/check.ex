defmodule ThistleTea.Game.Spell.PersistentArea.Check do
  @moduledoc """
  Boundary-sampled availability and hit roll for one ground source on a recipient.
  """

  defstruct [:hit_roll, available?: true]
end
