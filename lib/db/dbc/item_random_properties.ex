defmodule ItemRandomProperties do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "ItemRandomProperties" do
    field(:spell_item_enchantment_0, :integer)
    field(:spell_item_enchantment_1, :integer)
    field(:spell_item_enchantment_2, :integer)
    field(:suffix_en_gb, :string)
  end
end
