defmodule ThistleTea.DB.Mangos.CreatureGroup do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:member_guid, :integer, autogenerate: false}
  schema "creature_groups" do
    field(:leader_guid, :integer)
    field(:dist, :float)
    field(:angle, :float)
    field(:flags, :integer)
  end
end
