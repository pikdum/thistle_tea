defmodule ThistleTea.Game.Entity.Logic.PetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pet

  describe "dismiss/2" do
    test "clears live and recall state for a normal dismissal" do
      character = character_with_pet()

      assert {character, [%Effects.DismissPet{target_guid: 44}]} = Pet.dismiss(character)
      assert character.unit.summon == 0
      assert character.internal.active_pet_entry == nil
      assert character.internal.active_pet_spell_id == nil
    end

    test "retains recall state when the owner dies" do
      character = character_with_pet()

      assert {character, [%Effects.DismissPet{target_guid: 44}]} = Pet.dismiss(character, :owner_died)
      assert character.unit.summon == 0
      assert character.internal.active_pet_entry == 416
      assert character.internal.active_pet_spell_id == 688
    end

    test "does nothing without a live pet" do
      character = %{character_with_pet() | unit: %Unit{summon: 0}}

      assert {^character, []} = Pet.dismiss(character)
    end
  end

  defp character_with_pet do
    %Character{
      unit: %Unit{summon: 44},
      internal: %Internal{active_pet_entry: 416, active_pet_spell_id: 688}
    }
  end
end
