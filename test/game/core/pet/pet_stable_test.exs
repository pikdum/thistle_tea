defmodule ThistleTea.Game.Core.Pet.PetStableTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.PetProgress
  alias ThistleTea.Game.Core.Pet.PetStable

  setup [:character]

  describe "buy/2" do
    test "charges exactly once for each of two slots", %{character: character} do
      assert {:ok, character} = PetStable.buy(character, 500)
      assert character.player.coinage == 50_000
      assert character.internal.pet_stable.slots == 1
      assert {:ok, character} = PetStable.buy(character, 50_000)
      assert character.player.coinage == 0
      assert character.internal.pet_stable.slots == 2
      assert {:error, :stable} = PetStable.buy(character, 0)
    end

    test "rejects insufficient money and unavailable prices", %{character: character} do
      assert {:error, :money} = PetStable.buy(character, 50_501)
      assert {:error, :stable} = PetStable.buy(character, nil)
    end
  end

  describe "transfer/2" do
    test "requires a purchased empty slot and a hunter pet", %{character: character} do
      assert {:error, :stable} = PetStable.transfer(character, :store)
      assert {:ok, character} = PetStable.buy(character, 500)
      assert {:error, :stable} = PetStable.transfer(Companion.clear(character), :store)
      guardian = put_in(character.internal.companion.kind, :guardian)
      assert {:error, :stable} = PetStable.transfer(guardian, :store)
    end

    test "retains the complete pet record while clearing owner control", %{character: character} do
      character = put_in(character.internal.pet_stable.slots, 1)
      expected = character |> Companion.suspend() |> Companion.relationship()
      assert {:ok, stored} = PetStable.transfer(character, :store)
      assert stored.unit.summon == 0
      assert Companion.relationship(stored) == Companion.none()
      assert stored.internal.pet_stable.pets == %{1 => expected}
      assert {:ok, retrieved} = PetStable.transfer(stored, {:retrieve, 101})
      assert Companion.relationship(retrieved) == expected
      assert retrieved.internal.pet_stable.pets == %{}
    end

    test "distinguishes same-species pets and swaps into the vacated slot", %{character: character} do
      character = put_in(character.internal.pet_stable.slots, 1)
      assert {:ok, stored} = PetStable.transfer(character, :store)
      first = stored.internal.pet_stable.pets[1]
      second = %{first | pet_number: 202, happiness: 1, progress: %PetProgress{level: 12, xp: 99}}
      current = Companion.restore(stored, second)
      assert {:error, :stable} = PetStable.transfer(current, :store)
      assert {:error, :stable} = PetStable.transfer(current, {:swap, 999})
      assert {:ok, swapped} = PetStable.transfer(current, {:swap, 101})
      assert Companion.relationship(swapped) == first
      assert swapped.internal.pet_stable.pets[1] == second
      assert {:ok, swapped_back} = PetStable.transfer(swapped, {:retrieve, 202})
      assert Companion.relationship(swapped_back) == second
      assert swapped_back.internal.pet_stable.pets[1] == first
    end

    test "retrieval rejects an active current pet but accepts an empty current slot", %{character: character} do
      stored_pet = %{character.internal.companion | status: {:suspended, 69, 1515}, pet_number: 202}
      character = put_in(character.internal.pet_stable, %PetStable{slots: 1, pets: %{1 => stored_pet}})
      assert {:error, :stable} = PetStable.transfer(character, {:retrieve, 202})
      assert {:ok, _} = PetStable.transfer(character, {:swap, 202})
      empty = Companion.clear(character)
      assert {:error, :stable} = PetStable.transfer(empty, {:swap, 202})
      assert {:ok, _} = PetStable.transfer(empty, {:retrieve, 202})
    end

    test "preserves dead state and fills the first free purchased slot", %{character: character} do
      character = put_in(character.internal.companion.dead?, true)
      character = put_in(character.internal.pet_stable.slots, 2)
      assert {:ok, first} = PetStable.transfer(character, :store)
      second_pet = %{first.internal.pet_stable.pets[1] | pet_number: 202}
      assert {:ok, second} = first |> Companion.restore(second_pet) |> PetStable.transfer(:store)
      assert map_size(second.internal.pet_stable.pets) == 2
      assert {:ok, retrieved} = PetStable.transfer(second, {:retrieve, 101})
      assert retrieved.internal.companion.dead?
      assert {:ok, restored} = PetStable.transfer(retrieved, :store)
      assert restored.internal.pet_stable.pets[1].pet_number == 101
    end

    test "recall keeps the stable number while stale live GUID updates are ignored", %{character: character} do
      recalled =
        character
        |> Companion.suspend()
        |> Companion.activate(:hunter_pet, %EntityRef{guid: 303, entry: 69, spell_id: 883})

      assert recalled.internal.companion.pet_number == 101
      assert Companion.remember_progress(recalled, 101, %PetProgress{level: 1}) == recalled
      assert Companion.remember_death(recalled, 101) == recalled
    end
  end

  describe "entries/1" do
    test "uses client slots one through three", %{character: character} do
      character = put_in(character.internal.pet_stable.slots, 2)
      {:ok, stored} = PetStable.transfer(character, :store)
      current = Companion.restore(stored, %{stored.internal.pet_stable.pets[1] | pet_number: 202})
      assert [{1, %{pet_number: 202}}, {2, %{pet_number: 101}}] = PetStable.entries(current)
    end
  end

  defp character(_context) do
    pet = %Companion{
      kind: :hunter_pet,
      status: {:active, %EntityRef{guid: 101, entry: 69, spell_id: 1515}},
      pet_number: 101,
      happiness: 800_000,
      reaction_state: :passive,
      autocast: MapSet.new([2649]),
      progress: %PetProgress{
        level: 20,
        xp: 77,
        loyalty: 3,
        loyalty_points: 222,
        training_points: 33,
        spells: [2649, 24_547]
      }
    }

    %{
      character: %Character{
        unit: %Unit{summon: 101},
        player: %Player{coinage: 50_500},
        internal: %Internal{companion: pet}
      }
    }
  end
end
