defmodule PlayerCreateInfo do
  use Ecto.Schema

  @primary_key false
  schema "playercreateinfo" do
    field(:race, :integer)
    field(:class, :integer)
    field(:map, :integer)
    field(:zone, :integer)
    field(:position_x, :float)
    field(:position_y, :float)
    field(:position_z, :float)
    field(:orientation, :float)
  end

  def get(race, class) do
    ThistleTea.Mangos.get_by(PlayerCreateInfo, race: race, class: class)
  end
end
