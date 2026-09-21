defmodule ThistleTea.Game.World.Loader.ProfessionDBCTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.World.Loader.Skill

  @moduletag :dbc_db

  describe "vanilla profession catalog" do
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
