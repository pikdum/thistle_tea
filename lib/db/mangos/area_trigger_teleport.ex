defmodule ThistleTea.DB.Mangos.AreaTriggerTeleport do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "areatrigger_teleport" do
    field(:id, :integer)
    field(:patch, :integer)
    field(:name, :string)
    field(:message, :string)
    field(:required_level, :integer)
    field(:required_condition, :integer)
    field(:target_map, :integer)
    field(:target_position_x, :float)
    field(:target_position_y, :float)
    field(:target_position_z, :float)
    field(:target_orientation, :float)
  end
end
