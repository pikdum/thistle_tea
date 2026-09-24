defmodule ThistleTea.Game.Entity.Logic.CompanionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion, as: CompanionData
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects

  describe "activate/3" do
    test "possessing the current pet retains its identity and progression through release" do
      character =
        character_with_pet()
        |> Companion.capture_progress(%PetProgress{level: 49, xp: 123, spells: [2649]})
        |> Companion.capture_health(77)
        |> Companion.capture_happiness(750_000)
        |> Companion.remember_reaction(44, :passive)
        |> Companion.set_autocast([%{action: 14_920, action_type: 0xC1}])

      original = Companion.relationship(character)
      ref = %EntityRef{guid: 44, entry: 416, spell_id: 1002}
      possessed = Companion.activate(character, :possession, ref)
      assert Companion.relationship(possessed) == %{original | possession_spell_id: 1002}
      assert Companion.activate(possessed, :possession, ref) == possessed
      assert Companion.summon_guid(possessed) == 44
      assert Companion.control_guid(possessed) == 44
      assert possessed.unit.summon == 44
      assert possessed.unit.charm == 44

      released = Companion.removed(possessed, :released)
      assert Companion.relationship(released) == original
      assert Companion.control_guid(released) == nil
      assert released.unit.summon == 44
      assert released.unit.charm == 0
    end

    test "suspension and process loss clear possession while retaining the hunter pet" do
      possessed =
        Companion.activate(character_with_pet(), :possession, %EntityRef{guid: 44, entry: 416, spell_id: 1002})

      for transition <- [&Companion.suspend/1, &Companion.removed(&1, :process_down)] do
        suspended = transition.(possessed)
        assert Companion.suspended(suspended) == {:hunter_pet, 416, 688}
        assert Companion.relationship(suspended).possession_spell_id == nil
        assert Companion.control_guid(suspended) == nil
        assert suspended.unit.summon == 0
        assert suspended.unit.charm == 0
      end
    end
  end

  describe "dismiss/2" do
    test "suspends a hunter pet and clears the summon projection for a normal dismissal" do
      character = character_with_pet()

      assert {character, [%Effects.DismissPet{target_guid: 44}]} = Companion.dismiss(character)
      assert character.unit.summon == 0

      assert character.internal.companion ==
               %CompanionData{
                 kind: :hunter_pet,
                 status: {:suspended, 416, 688},
                 pet_number: 44,
                 restore_automatically?: false
               }

      assert Companion.suspend(character) == character
      restored = Companion.activate(character, :hunter_pet, %EntityRef{guid: 55, entry: 416, spell_id: 688})
      assert Companion.relationship(restored).restore_automatically?
      assert Companion.relationship(restored).pet_number == 44
    end

    test "suspends a hunter pet when the owner dies" do
      character = character_with_pet()

      assert {character, [%Effects.DismissPet{target_guid: 44}]} = Companion.dismiss(character, :owner_died)
      assert character.unit.summon == 0

      assert character.internal.companion ==
               %CompanionData{kind: :hunter_pet, status: {:suspended, 416, 688}, pet_number: 44}
    end

    test "ignores a stale summon projection without an active relationship" do
      character = %Character{unit: %Unit{summon: 44}, internal: %Internal{}}

      assert {dismissed, []} = Companion.dismiss(character)
      assert dismissed.unit.summon == 0
      assert dismissed.internal.companion == CompanionData.none()
    end

    test "releases controlled companions through the same transition" do
      character =
        %Character{object: %{guid: 7}, unit: %Unit{}, internal: %Internal{}}
        |> Companion.activate(:possession, %EntityRef{guid: 55, entry: 4277, spell_id: 126})

      assert {character, [%Effects.ReleaseControlled{source_guid: 7, target_guid: 55, spell_id: 126}]} =
               Companion.dismiss(character, :owner_died)

      assert character.unit.charm == 0
      assert character.internal.companion == CompanionData.none()
    end
  end

  describe "set_autocast/2" do
    test "preserves enabled spells across suspension and reactivation" do
      character =
        character_with_pet()
        |> Companion.set_autocast([%{action: 14_920, action_type: 0xC1}])
        |> Companion.suspend()
        |> Companion.activate(:hunter_pet, %EntityRef{guid: 55, entry: 416, spell_id: 688})

      assert Companion.autocast(character) == MapSet.new([14_920])
    end

    test "resets enabled spells when a different companion is activated" do
      character =
        character_with_pet()
        |> Companion.set_autocast([%{action: 14_920, action_type: 0xC1}])
        |> Companion.suspend()
        |> Companion.activate(:hunter_pet, %EntityRef{guid: 55, entry: 417, spell_id: 688})

      assert Companion.autocast(character) == MapSet.new()
    end
  end

  describe "remember_happiness/3" do
    test "preserves happiness through suspension and rejects stale pet updates" do
      character = Companion.remember_happiness(character_with_pet(), 44, 750_000)
      suspended = Companion.suspend(character)
      restored = Companion.activate(suspended, :hunter_pet, %EntityRef{guid: 55, entry: 416, spell_id: 688})

      assert Companion.relationship(suspended).happiness == 750_000
      assert Companion.relationship(restored).happiness == 750_000
      assert Companion.remember_happiness(restored, 44, 100) == restored
      assert Companion.remember_happiness(suspended, 44, 100) == suspended
      assert Companion.relationship(Companion.remember_happiness(restored, 55, 700_000)).happiness == 700_000
    end

    test "forgets happiness when the pet is abandoned or replaced" do
      character = Companion.remember_happiness(character_with_pet(), 44, 750_000)
      assert Companion.relationship(Companion.clear(character)).happiness == nil
      replaced = Companion.activate(character, :hunter_pet, %EntityRef{guid: 55, entry: 417, spell_id: 688})
      assert Companion.relationship(replaced).happiness == nil
    end
  end

  describe "remember_progress/3" do
    test "retains progress through suspension and rejects departed pet updates" do
      progress = %PetProgress{level: 49, xp: 123, spells: [2649]}
      character = Companion.remember_progress(character_with_pet(), 44, progress)
      suspended = Companion.suspend(character)
      restored = Companion.activate(suspended, :hunter_pet, %EntityRef{guid: 55, entry: 416, spell_id: 688})
      assert Companion.relationship(restored).progress == progress
      assert Companion.remember_progress(restored, 44, %PetProgress{level: 1}) == restored
      assert Companion.remember_progress(suspended, 44, %PetProgress{level: 1}) == suspended
      replaced = Companion.activate(restored, :hunter_pet, %EntityRef{guid: 66, entry: 417, spell_id: 688})
      assert Companion.relationship(replaced).progress == nil
      assert Companion.relationship(Companion.clear(restored)).progress == nil
    end
  end

  describe "remember_death/2" do
    test "retains death through suspension and clears it when revived" do
      character =
        character_with_pet() |> Companion.capture_health(77) |> Companion.remember_death(44) |> Companion.suspend()

      assert Companion.relationship(character).dead?
      assert Companion.relationship(character).health == 0
      restored = Companion.activate(character, :hunter_pet, %EntityRef{guid: 55, entry: 416, spell_id: 982})
      refute Companion.relationship(restored).dead?
      assert Companion.remember_death(restored, 44) == restored
    end
  end

  describe "remember_reaction/3" do
    test "retains stance through suspension and ignores replaced pets" do
      character = character_with_pet() |> Companion.remember_reaction(44, :passive) |> Companion.suspend()
      restored = Companion.activate(character, :hunter_pet, %EntityRef{guid: 55, entry: 416, spell_id: 688})
      assert Companion.relationship(restored).reaction_state == :passive
      assert Companion.remember_reaction(restored, 44, :aggressive) == restored
      changed = Companion.remember_reaction(restored, 55, :aggressive)
      assert Companion.relationship(changed).reaction_state == :aggressive
      replaced = Companion.activate(changed, :hunter_pet, %EntityRef{guid: 66, entry: 417, spell_id: 688})
      assert Companion.relationship(replaced).reaction_state == :defensive
    end
  end

  defp character_with_pet do
    %Character{unit: %Unit{}, internal: %Internal{}}
    |> Companion.activate(:hunter_pet, %EntityRef{guid: 44, entry: 416, spell_id: 688})
  end
end
