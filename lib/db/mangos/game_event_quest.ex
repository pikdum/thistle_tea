defmodule ThistleTea.DB.Mangos.GameEventQuest do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:quest, :integer, autogenerate: false}
  schema "game_event_quest" do
    field(:event, :integer)
    field(:patch_min, :integer)
  end
end
