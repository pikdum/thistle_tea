defmodule ThistleTea.DB.Mangos.CreatureEquipTemplate do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "creature_equip_template" do
    field(:equipentry1, :integer, default: 0)
    field(:equipentry2, :integer, default: 0)
    field(:equipentry3, :integer, default: 0)
  end
end
