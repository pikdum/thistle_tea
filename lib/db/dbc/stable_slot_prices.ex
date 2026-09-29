defmodule ThistleTea.DB.DBC.StableSlotPrices do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "StableSlotPrices" do
    field(:cost, :integer)
  end
end
