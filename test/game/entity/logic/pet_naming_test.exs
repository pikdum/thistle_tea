defmodule ThistleTea.Game.Entity.Logic.PetNamingTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetName
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.PetNaming
  alias ThistleTea.Game.Entity.Logic.PetStable

  setup [:build_pet]

  describe "valid?/1" do
    test "accepts two to twelve letters from one supported script" do
      for name <- ["Fang", "Éclair", "Волк", "白狼", "シロオオカミ", "늑대", "Abcdefghijkl"] do
        assert PetNaming.valid?(name), name
      end

      for name <- ["", "A", "Abcdefghijklm", "Wolf123", "White Wolf", "Fang!", "Woлf", <<255>>, nil] do
        refute PetNaming.valid?(name), inspect(name)
      end
    end
  end

  describe "rename/4" do
    test "changes the cache revision even within the same second and consumes permission", %{pet: pet} do
      assert {:ok, renamed, %PetName{name: "Fang", timestamp: 101}} = PetNaming.rename(pet, 7, "Fang", 100)
      assert renamed.internal.name == "Fang"
      assert renamed.unit.pet_name_timestamp == 101
      assert (renamed.unit.flags &&& 0x10) == 0
      assert (renamed.unit.flags &&& 0x08) == 0x08
      assert (renamed.unit.flags &&& 0x20) == 0x20
      assert renamed.internal.broadcast_update?
      assert PetNaming.rename(renamed, 7, "Claw", 102) == {:error, :unavailable}
    end

    test "rejects invalid names without consuming permission", %{pet: pet} do
      assert PetNaming.rename(pet, 7, "Bad Name", 100) == {:error, :invalid_name}
      assert {:ok, _, _} = PetNaming.rename(pet, 7, "Fang", 100)
    end

    test "rejects other owners, summons, broken bonds, and wild creatures", %{pet: pet} do
      assert PetNaming.rename(pet, 8, "Fang", 100) == {:error, :unavailable}
      assert PetNaming.rename(put_in(pet.internal.pet.kind, :summon), 7, "Fang", 100) == {:error, :unavailable}
      assert PetNaming.rename(put_in(pet.internal.pet.broken?, true), 7, "Fang", 100) == {:error, :unavailable}
      assert PetNaming.rename(put_in(pet.internal.pet, nil), 7, "Fang", 100) == {:error, :unavailable}
    end
  end

  describe "initialize/2" do
    test "retains names through dismissal, owner death, process loss, and stabling", %{pet: pet, owner: owner} do
      {:ok, _, identity} = PetNaming.rename(pet, 7, "Fang", 100)
      owner = Companion.remember_name(owner, pet.object.guid, identity)
      {dismissed, [_]} = Companion.dismiss(owner)

      for suspended <- [dismissed, Companion.removed(owner, :owner_died), Companion.removed(owner, :process_down)] do
        restored = Companion.activate(suspended, :hunter_pet, %EntityRef{guid: 101, entry: 69, spell_id: 1515})
        assert Companion.relationship(restored).name == identity
        projected = PetNaming.initialize(pet, Companion.relationship(restored).name)
        assert projected.internal.name == "Fang"
        assert projected.unit.pet_name_timestamp == 101
        assert (projected.unit.flags &&& 0x10) == 0
      end

      owner = put_in(owner.internal.pet_stable.slots, 1)
      assert {:ok, stored} = PetStable.transfer(owner, :store)
      assert stored.internal.pet_stable.pets[1].name == identity
      assert {:ok, retrieved} = PetStable.transfer(stored, {:retrieve, 100})
      assert Companion.relationship(retrieved).name == identity
    end

    test "does not give a new pet the previous pet's chosen name", %{pet: pet, owner: owner} do
      {:ok, _, identity} = PetNaming.rename(pet, 7, "Fang", 100)
      named = Companion.remember_name(owner, pet.object.guid, identity)
      assert Companion.remember_name(owner, pet.object.guid + 1, identity) == owner

      for {previous, kind, entry} <- [
            {named, :hunter_pet, 70},
            {named, :guardian, 69},
            {Companion.clear(named), :hunter_pet, 69}
          ] do
        next = Companion.activate(previous, kind, %EntityRef{guid: 102, entry: entry, spell_id: 1515})
        assert Companion.relationship(next).name == nil
      end
    end
  end

  defp build_pet(_context) do
    pet = %Mob{
      object: %Object{guid: 100},
      unit: %Unit{flags: 0x08, pet_name_timestamp: 100},
      internal: %Internal{name: "Boar", pet: %Pet{kind: :hunter, owner_guid: 7}}
    }

    owner = %Character{object: %Object{guid: 7}, unit: %Unit{}, internal: %Internal{}}
    owner = Companion.activate(owner, :hunter_pet, %EntityRef{guid: 100, entry: 69, spell_id: 1515})
    %{pet: PetNaming.initialize(pet, nil), owner: owner}
  end
end
