defmodule BankBagSlotPrices do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "BankBagSlotPrices" do
    field(:cost, :integer)
  end
end
