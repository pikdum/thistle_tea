defmodule ThistleTea.DB.Mangos.NpcTrainerTemplate do
  use Ecto.Schema

  @primary_key false
  schema "npc_trainer_template" do
    field(:entry, :integer)
    field(:spell, :integer)
    field(:spell_cost, :integer, source: :spellcost)
    field(:req_skill, :integer, source: :reqskill)
    field(:req_skill_value, :integer, source: :reqskillvalue)
    field(:req_level, :integer, source: :reqlevel)
  end
end
