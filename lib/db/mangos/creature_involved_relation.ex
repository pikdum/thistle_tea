defmodule ThistleTea.DB.Mangos.CreatureInvolvedRelation do
  use Ecto.Schema

  @primary_key false
  schema "creature_involvedrelation" do
    field(:id, :integer, primary_key: true, default: 0)
    field(:quest, :integer, primary_key: true, default: 0)
  end
end
