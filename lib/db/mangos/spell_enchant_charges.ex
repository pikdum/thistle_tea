defmodule ThistleTea.DB.Mangos.SpellEnchantCharges do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "spell_enchant_charges" do
    field(:charges, :integer)
  end
end
