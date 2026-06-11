defmodule ThistleTea.DB.Mangos.SpellTargetPosition do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "spell_target_position" do
    field(:target_map, :integer, default: 0)
    field(:target_position_x, :float, default: 0.0)
    field(:target_position_y, :float, default: 0.0)
    field(:target_position_z, :float, default: 0.0)
    field(:target_orientation, :float, default: 0.0)
  end
end
