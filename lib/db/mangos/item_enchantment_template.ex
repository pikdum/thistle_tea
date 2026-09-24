defmodule ThistleTea.DB.Mangos.ItemEnchantmentTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "item_enchantment_template" do
    field(:entry, :integer)
    field(:ench, :integer)
    field(:chance, :float)
    field(:patch_min, :integer)
    field(:patch_max, :integer)
  end
end
