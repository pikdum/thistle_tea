defmodule ThistleTea.DB.Mangos.QuestRelation do
  use Ecto.Schema

  @actor_creature 0
  @role_giver 0
  @role_ender 1

  @primary_key false
  schema "quest_relations" do
    field(:actor, :integer, primary_key: true, default: 0)
    field(:entry, :integer, primary_key: true, default: 0)
    field(:quest, :integer, primary_key: true, default: 0)
    field(:role, :integer, primary_key: true, default: 0)
  end

  def actor_creature, do: @actor_creature
  def role_giver, do: @role_giver
  def role_ender, do: @role_ender
end
