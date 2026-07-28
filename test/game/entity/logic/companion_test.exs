defmodule ThistleTea.Game.Entity.Logic.CompanionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion, as: CompanionData
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects

  describe "dismiss/2" do
    test "suspends a hunter pet and clears the summon projection for a normal dismissal" do
      character = character_with_pet()

      assert {character, [%Effects.DismissPet{target_guid: 44}]} = Companion.dismiss(character)
      assert character.unit.summon == 0

      assert character.internal.companion ==
               %CompanionData{kind: :hunter_pet, status: {:suspended, 416, 688}}
    end

    test "suspends a hunter pet when the owner dies" do
      character = character_with_pet()

      assert {character, [%Effects.DismissPet{target_guid: 44}]} = Companion.dismiss(character, :owner_died)
      assert character.unit.summon == 0

      assert character.internal.companion ==
               %CompanionData{kind: :hunter_pet, status: {:suspended, 416, 688}}
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

  defp character_with_pet do
    %Character{unit: %Unit{}, internal: %Internal{}}
    |> Companion.activate(:hunter_pet, %EntityRef{guid: 44, entry: 416, spell_id: 688})
  end
end
