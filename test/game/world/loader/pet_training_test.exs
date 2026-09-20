defmodule ThistleTea.Game.World.Loader.PetTrainingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.PetAbility
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.PetTraining

  describe "family_passives/3" do
    test "selects automatic passives from both family skills" do
      rows = [
        %SkillLineAbility{spell: 1, skill_line: 208, acquire_method: 2},
        %SkillLineAbility{spell: 2, skill_line: 270, acquire_method: 2},
        %SkillLineAbility{spell: 3, skill_line: 209, acquire_method: 2},
        %SkillLineAbility{spell: 4, skill_line: 208, acquire_method: 1},
        %SkillLineAbility{spell: 5, skill_line: 208, acquire_method: 2}
      ]

      spells = Map.new(1..4, &{&1, %Spell{id: &1, attributes: MapSet.new([:passive])}})
      spells = Map.put(spells, 5, %Spell{id: 5})
      assert Map.keys(PetTraining.family_passives(rows, spells, [208, 270])) == [1, 2]
    end
  end

  describe "build/2" do
    test "derives rank chains from skill successors and merges family eligibility" do
      rows = [
        %SkillLineAbility{spell: 100, skill_line: 208, training_points: 5, superseded_by: 101},
        %SkillLineAbility{spell: 100, skill_line: 209, training_points: 5, superseded_by: 101},
        %SkillLineAbility{spell: 101, skill_line: 208, training_points: 10, superseded_by: 0},
        %SkillLineAbility{spell: 999, skill_line: 270, training_points: 0, superseded_by: 0}
      ]

      catalogue = PetTraining.build(rows, %{100 => %Spell{id: 100}, 101 => %Spell{id: 101}})
      assert %PetAbility{cost: 5, skills: [208, 209], spell: %{first_in_chain: 100, rank: 1}} = catalogue[100]
      assert %PetAbility{cost: 10, spell: %{first_in_chain: 100, rank: 2}} = catalogue[101]
      refute Map.has_key?(catalogue, 999)
    end
  end
end
