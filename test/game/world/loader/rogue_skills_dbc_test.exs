defmodule ThistleTea.Game.World.Loader.RogueSkillsDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.World.Loader.Skill

  @moduletag :dbc_db

  describe "initial_skills/5" do
    test "Pick Lock and Poisons grant level-based rogue skills from vanilla data" do
      table = :ets.new(__MODULE__, [:set])
      Skill.load_all(table)
      skills = Skill.initial_skills([1804, 2842], 1, 4, 20, table)
      assert %{value: 1, max: 100, range: :level, always_max?: false} = skills[633]
      assert %{value: 1, max: 100, range: :level, always_max?: false} = skills[40]
      trained = Skills.max_out(skills)
      progressed = Skills.on_level_up(trained, 30)
      assert %{value: 100, max: 150} = progressed[633]
      assert Skill.initial_skills([2835], 1, 4, 20, table) == %{}
    end
  end
end
