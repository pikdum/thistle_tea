defmodule AuctionHouse do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "AuctionHouse" do
    field(:faction, :integer)
    field(:deposit_rate, :integer)
    field(:consignment_rate, :integer)
  end
end
