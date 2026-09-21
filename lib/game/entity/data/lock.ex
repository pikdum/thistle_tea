defmodule ThistleTea.Game.Entity.Data.Lock do
  @moduledoc """
  Ordered alternative keys and lock types from the vanilla lock catalog.
  """
  defstruct [:id, requirements: []]

  defmodule Requirement do
    @moduledoc false
    defstruct [:type, :index, skill: 0]
  end
end
