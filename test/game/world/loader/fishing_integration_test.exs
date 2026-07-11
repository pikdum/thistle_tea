defmodule ThistleTea.Game.World.Loader.FishingIntegrationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.Trainer
  alias ThistleTea.Game.World.Loader.Fishing
  alias ThistleTea.Game.World.Loader.Loot
  alias ThistleTea.Game.World.Loader.Trainer, as: TrainerLoader

  @moduletag :dbc_db
  @moduletag :vmangos_db

  setup do
    Fishing.load_all()
    Loot.load_fishing()
    :ok
  end

  describe "base_skill/2" do
    test "loads area difficulty with zone fallback" do
      assert Fishing.base_skill(327, 45) == 130
      assert Fishing.base_skill(999_999, 45) == 130
    end
  end

  describe "fishing trainer" do
    test "resolves apprentice and journeyman skill tiers" do
      spells = TrainerLoader.trainer_info(3179).spells
      apprentice = Enum.find(spells, &(&1.teach_spell_id == 7733))
      journeyman = Enum.find(spells, &(&1.teach_spell_id == 7734))

      assert {apprentice.learned_spell_id, apprentice.skill_id, apprentice.skill_max} == {7620, 356, 75}
      assert {journeyman.learned_spell_id, journeyman.skill_id, journeyman.skill_max} == {7731, 356, 150}
      assert Trainer.state(journeyman, [7620], 10, %{356 => %{value: 50}}) == :green
    end
  end

  describe "fishing loot" do
    test "generates area loot and falls back to the zone table" do
      assert %ThistleTea.Game.Entity.Logic.Loot{} = Loot.generate_fishing(327, 45)
      assert %ThistleTea.Game.Entity.Logic.Loot{} = Loot.generate_fishing(999_999, 45)
    end
  end
end
