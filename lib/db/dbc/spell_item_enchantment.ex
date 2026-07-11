defmodule SpellItemEnchantment do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "SpellItemEnchantment" do
    field(:enchantment_type_0, :integer)
    field(:enchantment_type_1, :integer)
    field(:enchantment_type_2, :integer)
    field(:effect_points_min_0, :integer)
    field(:effect_points_min_1, :integer)
    field(:effect_points_min_2, :integer)
    field(:effect_arg_0, :integer)
    field(:effect_arg_1, :integer)
    field(:effect_arg_2, :integer)
    field(:name_en_gb, :string)
    field(:item_visual, :integer)
    field(:flags, :integer)
  end
end
