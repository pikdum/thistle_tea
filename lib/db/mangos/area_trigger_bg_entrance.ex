defmodule ThistleTea.DB.Mangos.AreaTriggerBgEntrance do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "areatrigger_bg_entrance" do
    field(:name, :string)
    field(:team, :integer)
    field(:bg_template, :integer)
    field(:exit_map, :integer)
    field(:exit_position_x, :float)
    field(:exit_position_y, :float)
    field(:exit_position_z, :float)
    field(:exit_orientation, :float)
  end
end
