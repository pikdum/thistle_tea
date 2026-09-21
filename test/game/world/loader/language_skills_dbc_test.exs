defmodule ThistleTea.Game.World.Loader.LanguageSkillsDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.Skill

  @moduletag :dbc_db

  describe "initial_skills/5" do
    test "teaches Dwarven comprehension to a human who learns its spell" do
      table = :ets.new(__MODULE__, [:set])
      Skill.load_all(table)

      for race <- [1, 3] do
        skills = Skill.initial_skills([668, 672], race, 8, 50, table)
        assert %{value: 300, max: 300, range: :language} = skills[98]
        assert %{value: 300, max: 300, range: :language} = skills[111]
      end

      refute Map.has_key?(Skill.initial_skills([668], 1, 8, 50, table), 111)
    end
  end
end
