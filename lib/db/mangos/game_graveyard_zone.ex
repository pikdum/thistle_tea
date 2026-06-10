defmodule ThistleTea.DB.Mangos.GameGraveyardZone do
  use Ecto.Schema

  @primary_key false
  schema "game_graveyard_zone" do
    field(:id, :integer, primary_key: true, default: 0)
    field(:ghost_zone, :integer, primary_key: true, default: 0)
    field(:faction, :integer, default: 0)
  end
end
