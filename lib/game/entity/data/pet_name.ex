defmodule ThistleTea.Game.Entity.Data.PetName do
  @moduledoc "A hunter pet's chosen name and client cache revision, retained by its owner."

  @enforce_keys [:name, :timestamp]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: String.t(), timestamp: pos_integer()}
end
