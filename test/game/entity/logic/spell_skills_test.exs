defmodule ThistleTea.Game.Entity.Logic.SpellSkillsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellSkills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "learn/2" do
    test "preserves earned progress and stable slots when learning ranks in any order" do
      skills = %{} |> Skills.learn_rank(333, 75) |> Skills.learn_rank(186, 75)
      skills = put_in(skills[186].value, 60)
      grants = SpellSkills.grants(%{1 => rank(1, 186, 3), 2 => rank(2, 186, 1)})
      learned = SpellSkills.learn(skills, grants)
      assert %{value: 60, max: 225, step: 3} = learned[186]
      assert learned[186].slot == skills[186].slot
      assert learned[333] == skills[333]
      assert SpellSkills.learn(learned, SpellSkills.grants(rank(2, 186, 1))) == learned
    end
  end

  describe "grants/1" do
    test "uses trained riding values and ignores unrelated or invalid effects" do
      assert %{762 => %{value: 150, max: 150, step: 2}} = SpellSkills.grants(rank(1, 762, 2))
      assert SpellSkills.grants(rank(1, 0, 1)) == %{}
      assert SpellSkills.grants(rank(1, 186, 0)) == %{}
      assert SpellSkills.grants(%Spell{id: 1, effects: [%Effect{type: :learn_spell}]}) == %{}
    end
  end

  describe "remove/3" do
    test "clears lost grants and follows the remaining lower rank" do
      previous = SpellSkills.grants(%{1 => rank(1, 186, 2), 2 => rank(2, 333, 1)})
      current = SpellSkills.grants(rank(3, 186, 1))
      skills = put_in(previous[186].value, 100)
      removed = SpellSkills.remove(skills, previous, current)
      assert %{value: 1, max: 75, step: 1} = removed[186]
      assert removed[186].slot == skills[186].slot
      refute Map.has_key?(removed, 333)
      assert SpellSkills.remove(%{}, previous, current) == %{}
    end
  end

  defp rank(spell_id, skill_id, step) do
    %Spell{
      id: spell_id,
      effects: [%Effect{type: :skill, misc_value: skill_id, base_points: step - 1, base_dice: 1}]
    }
  end
end
