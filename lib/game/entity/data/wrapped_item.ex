defmodule ThistleTea.Game.Entity.Data.WrappedItem do
  @moduledoc """
  Original identity of a wrapped item. Ownership and mutable instance fields
  stay on the live item so opening cannot restore a former owner's snapshot.
  """
  @enforce_keys [:template, :flags]
  defstruct @enforce_keys
end
