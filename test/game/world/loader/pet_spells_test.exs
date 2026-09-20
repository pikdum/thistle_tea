defmodule ThistleTea.Game.World.Loader.PetSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.PetAbility
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.PetSpells

  describe "build/4" do
    test "retains exact beast ranks and charges each innate ability once" do
      bite = %Spell{id: 100}
      higher = %Spell{id: 101}
      passive = %Spell{id: 200, attributes: MapSet.new([:passive])}
      spells = %{100 => bite, 101 => higher, 200 => passive}

      abilities = %{
        100 => %PetAbility{spell: bite, cost: 4, skills: [208]},
        200 => %PetAbility{spell: passive, cost: 5, skills: [270]}
      }

      profile = PetSpells.build([100, 100, 200, 999], spells, %{300 => 100, 301 => 101, 400 => 200}, abilities)

      assert profile.spellbook == %{100 => bite, 200 => passive}
      assert profile.recipes == %{100 => 300, 200 => 400}
      assert profile.training_points == -9
    end

    test "unwraps creation recipes and preserves their explicit teaching spell" do
      spell = %Spell{id: 100}
      profile = PetSpells.build([300], %{100 => spell}, %{300 => 100, 301 => 100}, %{})
      assert profile.spellbook == %{100 => spell}
      assert profile.recipes == %{100 => 300}
    end

    test "keeps abilities without a recipe and gives empty beasts no spells" do
      assert %{spellbook: %{100 => _}, recipes: %{}, training_points: 0} =
               PetSpells.build([100], %{100 => %Spell{id: 100}}, %{}, %{})

      assert PetSpells.build([], %{100 => %Spell{id: 100}}, %{300 => 100}, %{}) == %{
               spellbook: %{},
               recipes: %{},
               training_points: 0
             }
    end
  end
end
