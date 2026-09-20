defmodule ThistleTea.Game.Entity.Data.PetProgress do
  @moduledoc """
  Hunter pet progression retained by the owner while the pet is suspended.
  """

  @enforce_keys [:level]
  defstruct [:level, :spells, xp: 0]

  @type t :: %__MODULE__{level: pos_integer(), xp: non_neg_integer(), spells: [pos_integer()] | nil}
end

defmodule ThistleTea.Game.Entity.Data.PetLevel do
  @moduledoc """
  Canonical hunter pet stats and experience requirement for one level.
  """

  @enforce_keys [:level, :health, :armor, :strength, :agility, :stamina, :intellect, :spirit, :next_level_xp]
  defstruct @enforce_keys
end
