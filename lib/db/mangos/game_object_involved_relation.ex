defmodule ThistleTea.DB.Mangos.GameObjectInvolvedRelation do
  use Ecto.Schema

  @primary_key false
  schema "gameobject_involvedrelation" do
    field(:id, :integer, primary_key: true, default: 0)
    field(:quest, :integer, primary_key: true, default: 0)
  end
end
