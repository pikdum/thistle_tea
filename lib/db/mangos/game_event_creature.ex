defmodule ThistleTea.DB.Mangos.GameEventCreature do
  use Ecto.Schema

  @primary_key {:guid, :integer, autogenerate: false}
  schema "game_event_creature" do
    field(:event, :integer, default: 0)
  end
end
