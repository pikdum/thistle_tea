defmodule ThistleTea.DB.Mangos.GameObjectQuestRelation do
  use Ecto.Schema

  @primary_key false
  schema "gameobject_questrelation" do
    field(:id, :integer, primary_key: true, default: 0)
    field(:quest, :integer, primary_key: true, default: 0)
  end
end
