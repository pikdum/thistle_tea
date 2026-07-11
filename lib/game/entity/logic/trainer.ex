defmodule ThistleTea.Game.Entity.Logic.Trainer do
  @moduledoc """
  Pure trainer-spell availability rules, mirroring the 1.12 client's
  green/red/gray spell states: gray when already known, red when a level,
  rank-chain, or skill requirement is unmet, green when learnable.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.TrainerSpell

  def fits_class_race?(%TrainerSpell{class_race_masks: []}, _class, _race), do: true

  def fits_class_race?(%TrainerSpell{class_race_masks: masks}, class, race) do
    class_bit = 1 <<< (class - 1)
    race_bit = 1 <<< (race - 1)

    Enum.any?(masks, fn {class_mask, race_mask} ->
      (class_mask == 0 or (class_mask &&& class_bit) != 0) and
        (race_mask == 0 or (race_mask &&& race_bit) != 0)
    end)
  end

  def state(%TrainerSpell{} = spell, known_ids, level, skills \\ %{}) do
    known_ids = known_ids || []

    cond do
      spell.learned_spell_id in known_ids -> :gray
      spell.req_level > level -> :red
      missing_prerequisite?(spell, known_ids) -> :red
      spell.req_skill > 0 and skill_value(skills, spell.req_skill) < spell.req_skill_value -> :red
      true -> :green
    end
  end

  defp skill_value(skills, skill_id) when is_map(skills) do
    case Map.get(skills, skill_id) do
      %{value: value} -> value
      _ -> 0
    end
  end

  defp skill_value(_skills, _skill_id), do: 0

  defp missing_prerequisite?(%TrainerSpell{prev_spell_id: prev, req_spell_id: req}, known_ids) do
    missing?(prev, known_ids) or missing?(req, known_ids)
  end

  defp missing?(nil, _known_ids), do: false
  defp missing?(spell_id, known_ids), do: spell_id not in known_ids
end
