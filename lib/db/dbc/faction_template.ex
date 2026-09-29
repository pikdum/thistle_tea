defmodule ThistleTea.DB.DBC.FactionTemplate do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "FactionTemplate" do
    field(:faction, :integer, default: 0)
    field(:flags, :integer, default: 0)
    field(:faction_group, :integer, default: 0)
    field(:friend_group, :integer, default: 0)
    field(:enemy_group, :integer, default: 0)
    field(:enemies_0, :integer, default: 0)
    field(:enemies_1, :integer, default: 0)
    field(:enemies_2, :integer, default: 0)
    field(:enemies_3, :integer, default: 0)
    field(:friends_0, :integer, default: 0)
    field(:friends_1, :integer, default: 0)
    field(:friends_2, :integer, default: 0)
    field(:friends_3, :integer, default: 0)
  end
end
