defmodule ThistleTea.Game.World.Loader.ProfessionDBCTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellSkills
  alias ThistleTea.Game.World.Loader.Skill
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "vanilla profession catalog" do
    test "initial ranks agree with loaded spell effects across professions and riding" do
      table = :ets.new(__MODULE__, [:set, :public])
      Skill.load_all(table)

      for {spell_id, skill_id, cap, value} <- [
            {2575, 186, 75, 1},
            {10_248, 186, 300, 1},
            {2550, 185, 75, 1},
            {18_260, 185, 300, 1},
            {3273, 129, 75, 1},
            {7620, 356, 75, 1},
            {33_388, 762, 75, 75},
            {33_391, 762, 150, 150}
          ] do
        initial = Skill.initial_skills([spell_id], 1, 1, 60, table)
        grants = SpellSkills.grants(SpellLoader.load(spell_id))
        assert initial[skill_id] == grants[skill_id]
        assert %{value: ^value, max: ^cap, range: :tier} = initial[skill_id]
      end
    end

    test "loads item-producing recipes and excludes ordinary class spells" do
      table = :ets.new(__MODULE__, [:set, :public])
      Skill.load_all(table)
      assert Skill.recipe(2657, table) == %{skill_id: 186, yellow: 25, gray: 70}
      assert Skill.recipe(2330, table) == %{skill_id: 171, yellow: 55, gray: 95}
      assert Skill.recipe(2538, table) == %{skill_id: 185, yellow: 45, gray: 85}
      assert Skill.recipe(5504, table) == nil
      assert Skill.recipe(nil, table) == nil
    end

    test "primary profession rules match every DBC skill category" do
      for line <- DBC.all(SkillLine) do
        assert Skills.primary_profession?(line.id) == (line.category == 11)
      end
    end

    test "all primary professions are abandonable and include their training spells" do
      table = :ets.new(__MODULE__, [:set, :public])
      Skill.load_all(table)

      for {skill, spell} <- [
            {164, 2018},
            {165, 2108},
            {171, 2259},
            {182, 2366},
            {186, 2575},
            {197, 3908},
            {202, 4036},
            {333, 7411},
            {393, 8613}
          ] do
        assert Skill.unlearnable?(skill, 1, 1, table)
        assert spell in Skill.spells(skill, table)
      end

      for skill <- [43, 95, 185, 129, 356] do
        refute Skill.unlearnable?(skill, 1, 1, table)
      end

      assert Enum.all?([2580, 2656, 2657, 2658, 2576, 10_248], &(&1 in Skill.spells(186, table)))
    end
  end
end
