defmodule QuestRelations do
  use Ecto.Schema

  @primary_key false
  schema "quest_relations" do
    field(:actor, :integer, default: 0)
    field(:entry, :integer, primary_key: true, default: 0)
    field(:quest, :integer, primary_key: true, default: 0)
    field(:role, :integer, primary_key: true, default: 0)
  end
end
