defmodule ThistleTea.Game.Entity.Data.VendorItem do
  @moduledoc false

  defstruct [:index, :template, :max_count, :condition, :price, :available, restock_seconds: 0, flags: 0]
end
