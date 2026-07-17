defmodule ThistleTea.DB.Mangos.SpellProcItemEnchant do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "spell_proc_item_enchant" do
    field(:ppm_rate, :float, source: :ppmRate)
  end
end
