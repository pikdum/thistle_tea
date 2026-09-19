defmodule ThistleTea.DBC.CreatureFamily do
  @moduledoc """
  Vanilla creature family diets. The converter labels DBC column seven as
  `category`; its `pet_food_mask` column actually contains the family skill id.
  """
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureFamily" do
    field(:pet_food_mask, :integer, source: :category)
  end
end
