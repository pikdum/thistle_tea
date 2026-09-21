defmodule ThistleTea.Game.Entity.Logic.PetProgressionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetLevel
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Effects.PetProgressChanged
  alias ThistleTea.Game.Entity.Logic.PetProgression
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell

  setup [:build_pet]

  describe "gain/4" do
    test "retains fractional progress and publishes one owner snapshot", %{pet: pet, levels: levels} do
      updated = PetProgression.gain(pet, 73, 12, levels)

      assert updated.unit.level == 8
      assert updated.unit.pet_experience == 73
      assert updated.unit.pet_next_level_exp == 1_350
      assert updated.unit.health == pet.unit.health
      assert updated.internal.pet.loyalty_points == 1_014

      assert [%PetProgressChanged{source_guid: 2, target_guid: 1, progress: %PetProgress{level: 8, xp: 73}}] =
               updated.internal.events
    end

    test "levels repeatedly and discards overflow at the owner cap", %{pet: pet, levels: levels} do
      updated = PetProgression.gain(pet, 100_000, 10, levels)

      assert updated.unit.level == 10
      assert updated.unit.pet_experience == 0
      assert updated.unit.pet_next_level_exp == 1_900
      assert updated.unit.health == 198
      assert updated.unit.power3 == 100
      assert updated.unit.power5 == pet.unit.power5
      assert updated.unit.strength == 31
      assert updated.unit.normal_resistance == 518
      assert updated.unit.min_damage > pet.unit.min_damage
      assert Stats.recompute(updated.unit) == updated.unit
      assert length(updated.internal.events) == 1
      assert PetProgression.gain(updated, 1_000, 10, levels) == updated
    end

    test "retains overflow below the cap and resumes when the owner levels", %{pet: pet, levels: levels} do
      updated = PetProgression.gain(pet, 1_500, 10, levels)
      assert updated.unit.level == 9
      assert updated.unit.pet_experience == 150
      capped = PetProgression.gain(updated, 2_000, 10, levels)
      resumed = PetProgression.gain(capped, 42, 11, levels)
      assert resumed.unit.level == 10
      assert resumed.unit.pet_experience == 42
    end

    test "preserves active buffs while replacing canonical growth inputs", %{pet: pet, levels: levels} do
      holder = %Holder{
        spell: %Spell{id: 10},
        auras: [%Aura{type: :mod_stat, misc_value: 2, amount: 5}, %Aura{type: :mod_attack_power, amount: 40}],
        stacks: 1
      }

      pet = %{pet | unit: %{pet.unit | auras: [holder]}}
      updated = PetProgression.gain(pet, 1_350, 10, levels)
      assert updated.unit.level == 9
      assert updated.unit.stamina == 34
      assert updated.unit.max_health == 226
      assert updated.unit.health == 226
      assert updated.unit.base_attack_power == 40
      assert updated.unit.attack_power == 80
      assert_in_delta updated.unit.min_damage, 9 * 1.15 * 1.05 * 1.3 * 1.25, 0.0001
      assert Stats.recompute(updated.unit) == updated.unit
      assert Stats.recompute(%{updated.unit | auras: []}).max_health == 176
      assert_in_delta Stats.recompute(%{updated.unit | auras: []}).min_damage, 9 * 1.15 * 1.05 * 1.25, 0.0001
    end

    test "level gains award training points before the kill loyalty bonus", %{pet: pet, levels: levels} do
      progress = %PetProgress{level: 8, loyalty: 3, loyalty_points: 16_999, training_points: 7}
      pet = PetProgression.initialize(pet, progress, levels)
      updated = PetProgression.gain(pet, 100_000, 10, levels)
      assert updated.unit.level == 10
      assert updated.unit.pet_loyalty == 4
      assert updated.internal.pet.training_points == 21
      assert updated.internal.pet.loyalty_points == 10_000
      assert updated.unit.training_points == -22
      assert length(updated.internal.events) == 1
      assert PetProgression.gain(updated, 100, 10, levels) == updated
    end

    test "ignores corpses, other companions, nonpositive rewards and capped pets", %{pet: pet, levels: levels} do
      dead = %{pet | unit: %{pet.unit | health: 0}}
      demon = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: :summon}}}
      capped = %{pet | unit: %{pet.unit | level: 60}}

      for other <- [dead, demon, capped], do: assert(PetProgression.gain(other, 2_000, 61, levels) == other)
      for amount <- [0, -1], do: assert(PetProgression.gain(pet, amount, 10, levels) == pet)
      assert PetProgression.gain(pet, 2_000, 8, levels) == pet
    end
  end

  describe "reward/2" do
    test "uses pet-level solo XP and the unmodified group share", %{pet: pet} do
      assert PetProgression.reward(pet, {:solo, 8, []}) == 85
      assert PetProgression.reward(pet, {:solo, 12, [elite?: true]}) == 204
      assert PetProgression.reward(pet, {:solo, 1, []}) == 0
      assert PetProgression.reward(pet, {:solo, 8, [extra_flags: 0x40]}) == 0
      assert PetProgression.reward(pet, {:group, 17}) == 17
    end
  end

  defp build_pet(_context) do
    levels =
      for {level, health, armor, strength, agility, stamina, cost} <- [
            {8, 156, 322, 29, 25, 28, 1_350},
            {9, 176, 412, 30, 26, 29, 1_625},
            {10, 198, 518, 31, 26, 30, 1_900}
          ],
          into: %{} do
        {level,
         %PetLevel{
           level: level,
           health: health,
           armor: armor,
           strength: strength,
           agility: agility,
           stamina: stamina,
           intellect: 22,
           spirit: 22,
           next_level_xp: cost
         }}
      end

    pet = %Mob{
      object: %Object{guid: 2},
      unit: %Unit{
        level: 8,
        health: 100,
        power3: 50,
        max_power3: 100,
        power5: 700_000,
        max_power5: 1_050_000,
        base_attack_time: 2_000,
        auras: []
      },
      internal: %Internal{pet: %Pet{kind: :hunter, owner_guid: 1}, events: []}
    }

    pet = PetProgression.initialize(pet, %PetProgress{level: 8}, levels)
    %{pet: %{pet | unit: %{pet.unit | health: 50, power3: 20}}, levels: levels}
  end
end
