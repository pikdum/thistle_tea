defmodule DurabilityCosts do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "DurabilityCosts" do
    for subclass <- 0..20, do: field(:"weapon_subclass_cost_#{subclass}", :integer)
    for subclass <- 0..7, do: field(:"armour_subclass_cost_#{subclass}", :integer)
  end
end
