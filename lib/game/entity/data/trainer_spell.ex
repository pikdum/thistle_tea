defmodule ThistleTea.Game.Entity.Data.TrainerSpell do
  @moduledoc """
  One spell a trainer teaches: the teaching spell shown in the trainer window,
  the spell it grants, its cost, and the level, skill, rank-chain, and
  class/race requirements to learn it.
  """
  defstruct [
    :teach_spell_id,
    :learned_spell_id,
    :prev_spell_id,
    :req_spell_id,
    cost: 0,
    req_level: 0,
    req_skill: 0,
    req_skill_value: 0,
    class_race_masks: []
  ]
end
