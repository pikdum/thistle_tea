defmodule ThistleTea.Game.Entity.Logic.SpellTeaching do
  @moduledoc "Player teaching effects and exact skill-step transitions over supplied spell data."

  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def effect?(%Effect{type: :learn_spell} = effect), do: not PetTraining.training_effect?(effect)
  def effect?(%Effect{type: :skill_step}), do: true
  def effect?(_effect), do: false

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &effect?/1)

  def spell_ids(%Spell{effects: effects}) do
    for %Effect{type: :learn_spell, trigger_spell_id: id} = effect <- effects,
        effect?(effect) and is_integer(id) and id > 0,
        uniq: true,
        do: id
  end

  def skill_steps(%Spell{effects: effects}) do
    for %Effect{type: :skill_step, misc_value: id} = effect <- effects,
        is_integer(id) and id > 0,
        step = Effect.damage_roll(effect),
        step >= 0,
        do: {id, step}
  end

  def apply_steps(skills, steps) do
    Enum.reduce(steps, skills || %{}, fn {id, step}, skills ->
      entry = Map.get(skills, id, %{value: 1, max: 0, range: :tier, always_max?: false, step: 0})
      entry = %{entry | value: max(entry.value, 1), max: step * 75, range: :tier}
      entry = Map.put(entry, :step, if(step > 0, do: step, else: Map.get(entry, :step, 0)))
      skills |> Map.put(id, entry) |> Skills.with_slots()
    end)
  end
end
