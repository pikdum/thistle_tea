defmodule ThistleTea.Game.Entity.Logic.PetSpellModifiersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.PetSpellModifiers
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "sync/4" do
    test "Endurance Training modifies the vanilla tamed-pet health passive" do
      spell = SpellLoader.load(19_581)

      pet = %Mob{
        object: %Object{guid: 2},
        unit: Stats.recompute(%Unit{level: 49, base_health: 2_138, health: 2_138, auras: []}),
        internal: %Internal{pet: %Pet{owner_guid: 1}, spellbook: %{spell.id => spell}}
      }

      pet = PetTraining.restore_passives(pet, 0)
      assert pet.unit.max_health == 2_138
      owner = %Character{object: %Object{guid: 1}, unit: %Unit{level: 50, auras: []}, internal: %Internal{}}
      {owner, _events} = Aura.apply_spell(owner, 1, 50, SpellLoader.load(19_587), 1)
      upgraded = PetSpellModifiers.sync(pet, 1, Modifiers.holders(owner), 2)
      assert upgraded.unit.max_health == 2_458
      assert hd(upgraded.unit.auras).auras |> hd() |> Map.fetch!(:amount) == 15
      assert PetSpellModifiers.sync(upgraded, 1, [], 3).unit.max_health == 2_138
    end
  end
end
