defmodule ThistleTea.DB.Mangos.SpellTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_template" do
    field(:entry, :integer)
    field(:build, :integer)
    field(:script_name, :string)
  end
end
