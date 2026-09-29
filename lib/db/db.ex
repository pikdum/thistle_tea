defmodule ThistleTea.DB do
  @moduledoc """
  Read-only seed databases: the VMangos world database (`DB.Mangos`) and the
  client DBC tables (`DB.DBC`). Only world loaders query them; loaded rows are
  translated into core structs and cached.
  """
  use Boundary, deps: [], exports: :all
end
