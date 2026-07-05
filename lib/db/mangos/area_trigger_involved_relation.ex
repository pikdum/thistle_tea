defmodule ThistleTea.DB.Mangos.AreaTriggerInvolvedRelation do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "areatrigger_involvedrelation" do
    field(:quest, :integer)
  end
end
