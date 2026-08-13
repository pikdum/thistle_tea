defmodule ThistleTea.DB.Mangos.GameObjectBattleground do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "gameobject_battleground" do
    field(:guid, :integer)
    field(:event1, :integer)
    field(:event2, :integer)
  end
end
