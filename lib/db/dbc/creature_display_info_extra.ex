defmodule CreatureDisplayInfoExtra do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureDisplayInfoExtra" do
    field(:display_race, :integer)
  end
end
