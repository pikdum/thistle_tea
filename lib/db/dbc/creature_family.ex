defmodule ThistleTea.DBC.CreatureFamily do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureFamily" do
    field(:pet_food_mask, :integer)
  end
end
