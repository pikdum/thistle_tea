defmodule ThistleTea.Game.Entity.Data.Companion.EntityRef do
  @moduledoc false

  @enforce_keys [:guid, :entry, :spell_id]
  defstruct [:guid, :entry, :spell_id]

  @type t :: %__MODULE__{
          guid: integer(),
          entry: non_neg_integer(),
          spell_id: non_neg_integer()
        }
end

defmodule ThistleTea.Game.Entity.Data.Companion do
  @moduledoc """
  Canonical relationship between a player and one controlled companion.

  Live process bookkeeping stays with the player owner; this value contains
  only stable domain identity and suspension data.
  """

  alias ThistleTea.Game.Entity.Data.Companion.EntityRef

  @type kind :: :hunter_pet | :guardian | :enslaved | :charm | :possession
  @type status :: :none | {:active, EntityRef.t()} | {:suspended, non_neg_integer(), non_neg_integer()}

  @enforce_keys [:kind, :status]
  defstruct [:kind, :status]

  @type t :: %__MODULE__{
          kind: kind() | nil,
          status: status()
        }

  def none, do: %__MODULE__{kind: nil, status: :none}
end
