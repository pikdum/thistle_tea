defmodule ThistleTea.Game.Core.Pet.PetAbility do
  @moduledoc """
  A trainable pet spell, its family eligibility, and cumulative training cost.
  """

  @enforce_keys [:spell, :skills, :cost]
  defstruct @enforce_keys
end
