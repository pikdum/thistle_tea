defmodule ThistleTea.DB.Mangos.SpellChain do
  use Ecto.Schema

  @primary_key {:spell_id, :integer, autogenerate: false}
  schema "spell_chain" do
    field(:prev_spell, :integer)
    field(:first_spell, :integer)
    field(:rank, :integer)
    field(:req_spell, :integer)
  end
end
