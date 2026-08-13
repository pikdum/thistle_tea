defmodule ThistleTea.DB.Mangos.CreatureBattleground do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "creature_battleground" do
    field(:guid, :integer)
    field(:event1, :integer)
    field(:event2, :integer)
  end
end
