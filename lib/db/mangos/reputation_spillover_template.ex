defmodule ThistleTea.DB.Mangos.ReputationSpilloverTemplate do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:faction, :integer, autogenerate: false}
  schema "reputation_spillover_template" do
    field(:faction_1, :integer, source: :faction1)
    field(:rate_1, :float)
    field(:rank_1, :integer)
    field(:faction_2, :integer, source: :faction2)
    field(:rate_2, :float)
    field(:rank_2, :integer)
    field(:faction_3, :integer, source: :faction3)
    field(:rate_3, :float)
    field(:rank_3, :integer)
    field(:faction_4, :integer, source: :faction4)
    field(:rate_4, :float)
    field(:rank_4, :integer)
  end
end
