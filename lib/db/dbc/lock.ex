defmodule Lock do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "Lock" do
    for index <- 0..7 do
      field(:"ty_#{index}", :integer)
      field(:"property_#{index}", :integer)
      field(:"required_skill_#{index}", :integer)
    end
  end
end
