defmodule ThistleTea.DB.Mangos.SpellCone do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "spell_cone" do
    field(:cone_degrees, :integer)
  end
end
