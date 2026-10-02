defmodule ThistleTea.DB.Mangos.PetNameGeneration do
  @moduledoc false
  use Ecto.Schema

  schema "pet_name_generation" do
    field(:word, :string)
    field(:entry, :integer)
    field(:half, :integer)
  end
end
