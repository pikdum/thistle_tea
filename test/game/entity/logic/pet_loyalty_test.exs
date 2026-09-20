defmodule ThistleTea.Game.Entity.Logic.PetLoyaltyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.AI.TickPlan
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Logic.PetProgression
  alias ThistleTea.Game.Network.UpdateObject

  setup [:build_pet]

  describe "tick/2" do
    test "starts a full interval and awards once per due callback", %{pet: pet} do
      started = PetLoyalty.tick(pet, 100)
      assert PetLoyalty.next_tick_at(started) == 12_100
      assert PetLoyalty.tick(started, 12_099) == started
      updated = PetLoyalty.tick(started, 12_100)
      assert updated.internal.pet.loyalty_points == 1_020
      assert PetLoyalty.next_tick_at(updated) == 24_100
      assert PetLoyalty.tick(updated, 12_100) == updated
      assert PetLoyalty.tick(updated, 100_000).internal.pet.loyalty_points == 1_040

      assert [%Effects.PetProgressChanged{source_guid: 2, target_guid: 1, progress: progress}] = updated.internal.events
      assert progress.loyalty_points == 1_020
    end

    test "uses the live happiness tier at exact thresholds", %{pet: pet} do
      for {happiness, delta} <- [{0, -20}, {332_999, -20}, {333_000, 10}, {665_999, 10}, {666_000, 20}] do
        pet = %{pet | unit: %{pet.unit | power5: happiness}}
        updated = pet |> PetLoyalty.tick(0) |> PetLoyalty.tick(12_000)
        assert updated.internal.pet.loyalty_points == 1_000 + delta
      end
    end

    test "maintenance contributes an independent deadline", %{pet: pet} do
      {:failure, pet, blackboard} = Regen.tick(pet, Blackboard.new(), 0)
      pet = %{pet | internal: %{pet.internal | blackboard: blackboard}}
      assert %TickPlan.Wake{at: 12_000, source: :pet_loyalty} in Tick.plan(pet, :success, 0).wakes
      {:failure, updated, _} = Regen.tick(pet, blackboard, 12_000)
      assert updated.internal.pet.loyalty_points == 1_020
    end

    test "ignores corpses and non-hunter companions", %{pet: pet} do
      dead = %{pet | unit: %{pet.unit | health: 0}}
      demon = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: :summon}}}

      for other <- [dead, demon] do
        assert PetLoyalty.tick(other, 100_000) == other
        assert PetLoyalty.next_tick_at(other) == nil
      end
    end

    test "death clears the deadline without changing loyalty and revival starts a full interval", %{pet: pet} do
      dead = pet |> PetLoyalty.tick(0) |> PetHappiness.on_death(false)
      assert dead.internal.pet.next_loyalty_at == nil
      assert dead.internal.pet.loyalty_points == 1_000
      revived = PetLoyalty.tick(dead, 100_000)
      assert revived.internal.pet.next_loyalty_at == 112_000
      assert revived.internal.pet.loyalty_points == 1_000
    end
  end

  describe "change/2" do
    test "promotes only above each threshold and awards the pet level in training points", %{pet: pet} do
      for {rank, threshold, next_start} <- [
            {1, 5_500, 4_500},
            {2, 11_500, 7_000},
            {3, 17_000, 10_000},
            {4, 23_500, 13_500},
            {5, 31_000, 17_500}
          ] do
        pet = PetLoyalty.initialize(pet, %PetProgress{level: 20, loyalty: rank, loyalty_points: threshold})
        assert PetLoyalty.change(pet, 0).unit.pet_loyalty == rank
        updated = PetLoyalty.change(pet, 1)
        assert updated.unit.pet_loyalty == rank + 1
        assert updated.internal.pet.loyalty_points == next_start
        assert updated.internal.pet.training_points == 20
        assert updated.unit.training_points == -21
        assert updated.internal.broadcast_update?
      end
    end

    test "demotes below zero and permits training debt", %{pet: pet} do
      pet = PetLoyalty.initialize(pet, %PetProgress{level: 20, loyalty: 3, loyalty_points: 0, training_points: 5})
      assert PetLoyalty.change(pet, 0) == pet
      updated = PetLoyalty.change(pet, -1)
      assert updated.unit.pet_loyalty == 2
      assert updated.internal.pet.loyalty_points == 4_500
      assert updated.internal.pet.training_points == -15
      assert updated.unit.training_points == 15
    end

    test "best friends ignore overflowing gains but can lose loyalty", %{pet: pet} do
      pet = PetLoyalty.initialize(pet, %PetProgress{level: 20, loyalty: 6, loyalty_points: 39_490})
      assert PetLoyalty.change(pet, 20) == pet
      assert PetLoyalty.change(pet, 10).internal.pet.loyalty_points == 39_500
      assert PetLoyalty.change(pet, -20).internal.pet.loyalty_points == 39_470
    end

    test "a rebellious pet breaks its bond once and stops progressing", %{pet: pet} do
      pet = PetLoyalty.initialize(pet, %PetProgress{level: 20, loyalty_points: 0})
      broken = pet |> PetLoyalty.tick(0) |> PetLoyalty.change(-1)
      assert broken.internal.pet.broken?
      assert broken.internal.pet.loyalty_points == 0
      assert broken.internal.pet.next_loyalty_at == nil
      assert PetLoyalty.next_tick_at(broken) == nil
      assert [%Effects.PetBroke{source_guid: 2, target_guid: 1}] = broken.internal.events
      assert PetLoyalty.change(broken, 10_000) == broken
      assert PetLoyalty.tick(broken, 100_000) == broken
    end

    test "increasing loyalty reduces subsequent happiness decay", %{pet: pet} do
      promoted = PetLoyalty.change(pet, 4_501)
      before = pet |> PetHappiness.tick(0) |> PetHappiness.tick(7_500)
      after_promotion = promoted |> PetHappiness.tick(0) |> PetHappiness.tick(7_500)
      assert pet.unit.power5 - before.unit.power5 == 8_750
      assert pet.unit.power5 - after_promotion.unit.power5 == 4_375
    end
  end

  describe "initialize/2" do
    test "restores retained loyalty and training without an elapsed timer", %{pet: pet} do
      progress = %PetProgress{level: 20, loyalty: 4, loyalty_points: 12_345, training_points: 45}
      restored = PetLoyalty.initialize(pet, progress)
      assert restored.unit.pet_loyalty == 4
      assert restored.unit.training_points == -46
      assert restored.internal.pet.next_loyalty_at == nil
      assert %{loyalty: 4, loyalty_points: 12_345, training_points: 45} = PetProgression.snapshot(restored)
    end

    test "encodes signed training-point presentation in a complete private field", %{pet: pet} do
      for {points, encoded} <- [{0, 0xFFFFFFFF}, {20, 0xFFFFFFEB}, {-15, 15}] do
        pet = PetLoyalty.initialize(pet, %PetProgress{level: 20, training_points: points})
        field = Enum.find(UpdateObject.flatten_field_structs([pet.unit], :self), &match?({:training_points, _, _}, &1))
        assert UpdateObject.field(field) == <<encoded::little-size(32)>>
        refute Enum.any?(UpdateObject.flatten_field_structs([pet.unit], :other), &match?({:training_points, _, _}, &1))
      end
    end
  end

  defp build_pet(_context) do
    pet = %Mob{
      object: %Object{guid: 2},
      unit: %Unit{health: 100, max_health: 100, level: 20, power5: 700_000, max_power5: 1_050_000, pet_loyalty: 1},
      internal: %Internal{pet: %Pet{kind: :hunter, owner_guid: 1}, events: []}
    }

    %{pet: pet}
  end
end
