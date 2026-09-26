defmodule ThistleTea.DB.Mangos.SpellElixir do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_elixir" do
    field(:entry, :integer)
    field(:mask, :integer)
    field(:build_min, :integer)
    field(:build_max, :integer)
  end
end
