defmodule ThistleTea.Game.World.Loader.SkillTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.Skill

  setup do
    table = :ets.new(__MODULE__, [:set, :public])

    Skill.load(
      [%SkillLine{id: 186, category: 11}, %SkillLine{id: 43, category: 6}],
      [
        %SkillRaceClassInfo{skill_line: 186, race_mask: 1, class_mask: 1, flags: 0x20, skill_tier: 2},
        %SkillRaceClassInfo{skill_line: 43, race_mask: 0, class_mask: 0, flags: 0, skill_tier: 0}
      ],
      [
        ability(186, 2575, 0, 0),
        ability(186, 2657, 1, 1),
        ability(186, 2658, 0, 50),
        ability(43, 201, 2, 0)
      ],
      table
    )

    %{table: table}
  end

  describe "unlearnable?/4" do
    test "requires the flag and matching race and class", %{table: table} do
      assert Skill.unlearnable?(186, 1, 1, table)
      refute Skill.unlearnable?(186, 2, 1, table)
      refute Skill.unlearnable?(186, 1, 2, table)
      refute Skill.unlearnable?(43, 1, 1, table)
      refute Skill.unlearnable?(999, 1, 1, table)
    end
  end

  describe "spells/2" do
    test "includes ranks, automatic rewards, and purchased recipes", %{table: table} do
      assert Skill.spells(186, table) == [2575, 2657, 2658]
    end
  end

  describe "reward_spells/5" do
    test "only grants eligible automatic rewards", %{table: table} do
      assert Skill.reward_spells(186, 1, 1, 1, table) == [2657]
      assert Skill.reward_spells(186, 0, 1, 1, table) == []
      assert Skill.reward_spells(nil, 1, 1, 1, table) == []
    end
  end

  describe "initial_skills/5" do
    test "derives weapon skills without recreating tiered professions", %{table: table} do
      assert Skill.initial_skills([201, 2575], 1, 1, 20, table) ==
               %{43 => %{value: 1, max: 100, range: :level, always_max?: false, slot: 0}}
    end

    test "derives rogue class skills from base abilities, excluding recipes and other classes", %{table: table} do
      Skill.load(
        [%SkillLine{id: 633, category: 7}, %SkillLine{id: 40, category: 7}],
        for(
          id <- [40, 633],
          do: %SkillRaceClassInfo{skill_line: id, race_mask: 0, class_mask: 8, flags: 128, skill_tier: 0}
        ),
        [
          %{ability(633, 1804, 0, 0) | trivial_skill_line_rank_high: 0},
          %{ability(40, 2842, 0, 0) | trivial_skill_line_rank_high: 0},
          %{ability(40, 2835, 0, 0) | trivial_skill_line_rank_high: 225}
        ],
        table
      )

      skills = Skill.initial_skills([1804, 2842], 1, 4, 20, table)
      assert skills[633].value == 1
      assert skills[633].max == 100
      assert skills[40].value == 1
      assert skills[40].max == 100
      assert Skill.initial_skills([2835], 1, 4, 20, table) == %{}
      assert Skill.initial_skills([1804, 2842], 1, 1, 20, table) == %{}
    end
  end

  defp ability(skill, spell, method, rank) do
    %SkillLineAbility{
      skill_line: skill,
      spell: spell,
      acquire_method: method,
      min_skill_line_rank: rank,
      race_mask: 0,
      class_mask: 0
    }
  end
end
