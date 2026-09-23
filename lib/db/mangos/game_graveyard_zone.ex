defmodule ThistleTea.DB.Mangos.GameGraveyardZone do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "game_graveyard_zone" do
    field(:id, :integer, primary_key: true, default: 0)
    field(:ghost_zone, :integer, primary_key: true, default: 0)
    field(:faction, :integer, default: 0)
    field(:patch_min, :integer)
    field(:patch_max, :integer)
  end
end
