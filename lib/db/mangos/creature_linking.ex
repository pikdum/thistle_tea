defmodule ThistleTea.DB.Mangos.CreatureLinking do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:guid, :integer, autogenerate: false}
  schema "creature_linking" do
    field(:master_guid, :integer)
    field(:flag, :integer)
  end
end
