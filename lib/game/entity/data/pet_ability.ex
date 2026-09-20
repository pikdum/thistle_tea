defmodule ThistleTea.Game.Entity.Data.PetAbility do
  @moduledoc """
  A trainable pet spell, its family eligibility, and cumulative training cost.
  """

  @enforce_keys [:spell, :skills, :cost]
  defstruct @enforce_keys
end
