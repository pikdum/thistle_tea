defmodule ThistleTea.DB.Mangos.BattlegroundEvent do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "battleground_events" do
    field(:map, :integer)
    field(:event1, :integer)
    field(:event2, :integer)
    field(:description, :string)
  end
end
