defmodule ThistleTea.Game.Entity.Logic.PetUntrainingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.PetProgression
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.PetUntraining
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect

  setup [:build_pet]

  describe "cost/2" do
    test "escalates through silver and gold prices up to ten gold" do
      assert PetUntraining.cost(%Pet{}, -100_000) == 1_000

      for {previous, expected} <- [
            {1_000, 5_000},
            {5_000, 10_000},
            {10_000, 20_000},
            {90_000, 100_000},
            {100_000, 100_000}
          ] do
        assert PetUntraining.cost(%Pet{last_untrain_at: -100_000, last_untrain_cost: previous}, 0) == expected
      end
    end

    test "returns to ten silver after a full day since the latest reset" do
      control = %Pet{last_untrain_at: -100_000, last_untrain_cost: 50_000}
      assert PetUntraining.cost(control, -100_000 + 86_399_999) == 60_000
      assert PetUntraining.cost(control, -100_000 + 86_400_000) == 1_000
    end
  end

  describe "reset/6" do
    test "refunds points and removes abilities and their stats while preserving family passives and buffs", %{
      pet: pet,
      family: family
    } do
      assert pet.unit.stamina == 38
      assert {:ok, updated, 1_000} = PetUntraining.reset(pet, 1, 1_000, 1_000, family, 500)
      assert updated.unit.stamina == 33
      assert updated.unit.max_health == pet.unit.max_health - 50
      assert updated.internal.spellbook == family
      assert updated.internal.creature.spells == []
      assert updated.internal.casting == nil
      assert updated.internal.pet.training_points == 60
      assert updated.unit.training_points == -61
      assert updated.internal.pet.autocast == MapSet.new()
      assert updated.internal.pet.action_bar == %{0 => {2, 7}, 3 => {0, 0x81}, 4 => {0, 0x81}, 9 => {0, 6}}
      assert updated.unit.auras |> Enum.map(& &1.spell.id) |> Enum.sort() == [300, 400]

      assert %{spells: [], training_points: 60, last_untrain_at: 500, last_untrain_cost: 1_000} =
               PetProgression.snapshot(updated)

      assert {:ok, 5_000} = PetUntraining.quote(updated, 1, 501)
    end

    test "rejects insufficient funds and an obsolete price without changing the pet", %{pet: pet, family: family} do
      assert {:error, :not_enough_money} = PetUntraining.reset(pet, 1, 999, 1_000, family, 0)
      assert {:error, :not_enough_money} = PetUntraining.reset(pet, 1, 10_000, 999, family, 0)
      assert pet.internal.pet.last_untrain_at == nil
      assert pet.internal.pet.training_points == -5
    end

    test "can reset a corpse without resurrecting it", %{pet: pet, family: family} do
      dead = %{pet | unit: %{pet.unit | health: 0}}
      assert {:ok, updated, 1_000} = PetUntraining.reset(dead, 1, 1_000, 1_000, family, 0)
      assert updated.unit.health == 0
      assert updated.internal.pet.training_points == 60
    end
  end

  describe "quote/3" do
    test "requires ownership and an ordinary hunter pet with multiple known spells", %{pet: pet} do
      assert {:error, :no_pet} = PetUntraining.quote(pet, 2, 0)

      for control <- [
            %{pet.internal.pet | kind: :summon},
            %{pet.internal.pet | broken?: true},
            %{pet.internal.pet | possessed?: true}
          ] do
        assert {:error, :no_pet} = PetUntraining.quote(%{pet | internal: %{pet.internal | pet: control}}, 1, 0)
      end

      assert {:error, :no_pet} =
               PetUntraining.quote(%{pet | internal: %{pet.internal | spellbook: %{100 => %Spell{id: 100}}}}, 1, 0)
    end
  end

  defp build_pet(_context) do
    trained = %Spell{
      id: 200,
      attributes: MapSet.new([:passive]),
      duration_ms: -1,
      effects: [%Effect{type: :apply_aura, aura: :mod_stat, misc_value: 2, base_points: 5, implicit_target_a: :caster}]
    }

    family = Map.new([300, 301], &{&1, %Spell{id: &1, attributes: MapSet.new([:passive])}})

    holders = [
      %Holder{spell: family[300], auras: [], stacks: 1},
      %Holder{spell: %Spell{id: 400}, auras: [%Aura{type: :mod_stat, misc_value: 2, amount: 3}], stacks: 1}
    ]

    pet = %Mob{
      object: %Object{guid: 2},
      unit:
        Stats.recompute(%Unit{
          health: 100,
          level: 20,
          pet_loyalty: 4,
          base_stamina: 30,
          base_health: 100,
          auras: holders
        }),
      internal: %Internal{
        pet: %Pet{
          owner_guid: 1,
          kind: :hunter,
          training_points: -5,
          family_spells: MapSet.new(Map.keys(family)),
          autocast: MapSet.new([100]),
          action_bar: %{0 => {2, 7}, 3 => {100, 0xC1}, 4 => {200, 1}, 9 => {0, 6}}
        },
        casting: %Cast{spell: %Spell{id: 100}},
        creature: %Creature{},
        spellbook: Map.merge(family, %{100 => %Spell{id: 100}, 200 => trained})
      }
    }

    %{pet: PetTraining.restore_passives(pet, 0), family: family}
  end
end
