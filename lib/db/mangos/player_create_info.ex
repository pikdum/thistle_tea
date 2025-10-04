defmodule ThistleTea.DB.Mangos.PlayerCreateInfo do
  use Ecto.Schema

  alias ThistleTea.DB.Mangos

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
    Mangos.Repo.get_by(Mangos.PlayerCreateInfo, race: race, class: class)
  end
end
