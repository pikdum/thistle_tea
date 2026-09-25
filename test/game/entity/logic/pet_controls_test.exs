defmodule ThistleTea.Game.Entity.Logic.PetControlsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.PetControls
  alias ThistleTea.Game.Network.Message.SmsgPetSpells
  alias ThistleTea.Game.Spell

  setup [:build_pet]

  describe "update/3" do
    test "toggles every copy and projects manual-only spells without autocast", %{pet: pet} do
      {:ok, pet} = PetControls.update(pet, 1, {:actions, [action(5, 100, 0x81)]})
      {:ok, enabled} = PetControls.update(pet, 1, {:autocast, 100, true})
      assert enabled.internal.pet.autocast == MapSet.new([100])
      assert enabled.internal.pet.action_bar[3] == {100, 0xC1}
      assert enabled.internal.pet.action_bar[5] == {100, 0xC1}
      {:ok, disabled} = PetControls.update(enabled, 1, {:autocast, 100, false})
      assert disabled.internal.pet.autocast == MapSet.new()
      assert disabled.internal.pet.action_bar[5] == {100, 0x81}

      packet = SmsgPetSpells.for_pet(123, Map.values(pet.internal.spellbook), enabled.internal.pet)
      assert (200 + Bitwise.bsl(0x01, 24)) in packet.spells
      assert (100 + Bitwise.bsl(0xC1, 24)) in packet.spells
    end

    test "rejects unknown, passive, and manual-only autocast spells", %{pet: pet} do
      for id <- [200, 300, 999], enabled? <- [true, false] do
        assert {:error, :invalid_spell} = PetControls.update(pet, 1, {:autocast, id, enabled?})
      end
    end

    test "rejects stale owners and disabled controls", %{pet: pet} do
      assert {:error, :not_controlled} = PetControls.update(pet, 2, {:autocast, 100, true})

      for control <- [%{pet.internal.pet | possessed?: true}, %{pet.internal.pet | broken?: true}, nil] do
        disabled = %{pet | internal: %{pet.internal | pet: control}}
        assert {:error, :not_controlled} = PetControls.update(disabled, 1, {:autocast, 100, true})
      end
    end

    test "accepts command swaps and rejects command removal or duplication", %{pet: pet} do
      {:ok, moved} = PetControls.update(pet, 1, {:actions, [action(3, 2, 0x07), action(0, 100, 0x81)]})
      assert moved.internal.pet.action_bar[3] == {2, 0x07}
      assert moved.internal.pet.action_bar[0] == {100, 0x81}

      for changes <- [
            [action(0, 0, 0x81)],
            [action(3, 2, 0x07)],
            [action(3, 2, 0x07), action(4, 100, 0x81)]
          ] do
        assert {:error, :invalid_action} = PetControls.update(pet, 1, {:actions, changes})
      end
    end

    test "validates an entire edit before applying either half", %{pet: pet} do
      for invalid <- [
            action(10, 100, 0x81),
            action(4, 999, 0x81),
            action(4, 300, 0x01),
            action(4, 200, 0xC1),
            action(4, 100, 0xFF),
            action(3, 100, 0x81)
          ] do
        assert {:error, :invalid_action} =
                 PetControls.update(pet, 1, {:actions, [action(3, 100, 0xC1), invalid]})
      end
    end

    test "restores moved buttons and filters obsolete or ineligible spell settings", %{pet: pet} do
      {:ok, moved} = PetControls.update(pet, 1, {:actions, [action(7, 100, 0xC1), action(3, 2, 0x06)]})
      bar = Map.put(moved.internal.pet.action_bar, 4, {999, 0x81})
      {:ok, restored} = PetControls.update(pet, 1, {:restore, bar, MapSet.new([100, 200, 300, 999])})
      assert restored.internal.pet.action_bar[7] == {100, 0xC1}
      assert restored.internal.pet.action_bar[3] == {2, 0x06}
      assert restored.internal.pet.action_bar[4] == {0, 0x81}
      assert restored.internal.pet.autocast == MapSet.new([100])
    end
  end

  defp build_pet(_context) do
    spells = [
      %Spell{id: 100},
      %Spell{id: 200, attributes: MapSet.new([:no_autocast_ai])},
      %Spell{id: 300, attributes: MapSet.new([:passive])}
    ]

    pet = %Mob{internal: %Internal{pet: %Pet{owner_guid: 1}, spellbook: Map.new(spells, &{&1.id, &1})}}
    %{pet: pet}
  end

  defp action(slot, id, type), do: %{position: slot, action: id, action_type: type}
end
