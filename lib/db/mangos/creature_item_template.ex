defmodule ThistleTea.DB.Mangos.CreatureItemTemplate do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "creature_item_template" do
    field(:class, :integer, default: 0)
    field(:subclass, :integer, default: 0)
    field(:material, :integer, default: 0)
    field(:display_id, :integer, default: 0, source: :displayid)
    field(:inventory_type, :integer, default: 0)
    field(:sheath_type, :integer, default: 0)
  end
end
