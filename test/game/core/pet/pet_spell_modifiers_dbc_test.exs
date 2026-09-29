defmodule ThistleTea.Game.Core.Pet.PetSpellModifiersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.PetSpellModifiers
  alias ThistleTea.Game.Core.Pet.PetTraining
  alias ThistleTea.Game.Core.Spell.Modifiers
  alias ThistleTea.Game.Core.Stats
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
