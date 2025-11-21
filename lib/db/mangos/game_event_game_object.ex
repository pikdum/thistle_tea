defmodule ThistleTea.DB.Mangos.GameEventGameObject do
  use Ecto.Schema

  @primary_key {:guid, :integer, autogenerate: false}
  schema "game_event_gameobject" do
    field(:event, :integer, default: 0)
  end
end
