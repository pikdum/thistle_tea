defmodule ThistleTea.Game.Core.Pet.PetResurrectionTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.PetHappiness
  alias ThistleTea.Game.Core.Pet.PetResurrection
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect.SummonControl
  alias ThistleTea.Game.Core.WorldRef

  setup [:dead_pet]

  describe "revive/4" do
    test "revives summoned pets and guardians without restoring mana", %{pet: pet, context: context} do
      for kind <- [:summon, :guardian, :creature_pet] do
        summoned = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: kind}}}
        {revived, _events} = PetResurrection.revive(summoned, context, 70, 2_000)
        assert revived.unit.health == 70
        assert revived.unit.power1 == 12
        assert revived.internal.pet.kind == kind
      end
    end

    test "restores flat health and position while retaining identity, resources, training, and controls", %{
      pet: pet,
      context: context
    } do
      {revived, events} = PetResurrection.revive(pet, context, 70, 2_000)
      assert revived.object == pet.object
      assert revived.unit.health == 70
      assert revived.unit.power1 == 12
      assert revived.unit.power5 == pet.unit.power5
      assert revived.unit.pet_number == 123
      assert revived.internal.pet == pet.internal.pet
      assert revived.internal.spellbook == pet.internal.spellbook
      assert revived.movement_block.position == {10.0, 20.0, 30.0, 1.5}
      assert (revived.unit.flags &&& 0x04040000) == 0
      assert revived.unit.dynamic_flags == 0
      refute revived.internal.death_finalized?
      assert revived.internal.killed_by == nil
      assert revived.internal.broadcast_update?
      assert [%Effects.CreatureTeleported{}, %Effects.PetRevived{source_guid: 100, target_guid: 1, health: 70}] = events
      assert PetResurrection.revive(revived, context, 70, 2_001) == {revived, []}
    end

    test "clamps health without granting the player resurrection mana amount", %{pet: pet, context: context} do
      effect = %Effect{type: :resurrect_new, base_points: 399, misc_value: 700}
      {revived, _events} = SummonControl.apply(pet, context, %Spell{id: 20_484}, effect, 2_000)
      assert revived.unit.health == 100
      assert revived.unit.power1 == 12
      {revived, _events} = PetResurrection.revive(pet, context, 0, 2_000)
      assert revived.unit.health == 1
    end

    test "rejects ordinary creatures, charms, broken bonds, foreign worlds, and percent resurrection", %{
      pet: pet,
      context: context
    } do
      for control <- [
            nil,
            %{pet.internal.pet | kind: :charmed},
            %{pet.internal.pet | kind: :possessed},
            %{pet.internal.pet | broken?: true}
          ] do
        other = %{pet | internal: %{pet.internal | pet: control}}
        assert PetResurrection.revive(other, context, 70, 2_000) == {other, []}
      end

      other = %{context | caster_position: {WorldRef.open(2), 10.0, 20.0, 30.0}}
      assert PetResurrection.revive(pet, other, 70, 2_000) == {pet, []}

      assert SummonControl.apply(pet, context, %Spell{id: 8342}, %Effect{type: :resurrect, base_points: 14}, 2_000) ==
               {pet, []}
    end
  end

  describe "corpse_expired?/2" do
    test "invalidates old expiry messages across revival and a later death", %{pet: pet, context: context} do
      generation = pet.internal.pet.corpse_generation
      assert PetResurrection.corpse_expired?(pet, generation)
      {revived, _events} = PetResurrection.revive(pet, context, 70, 2_000)
      refute PetResurrection.corpse_expired?(revived, generation)
      dead = revived |> Entity.kill(3_000) |> PetResurrection.prepare_corpse()
      dead = %{dead | internal: %{dead.internal | death_finalized?: true}}
      refute PetResurrection.corpse_expired?(dead, generation)
      assert PetResurrection.corpse_expired?(dead, generation + 1)
    end
  end

  describe "corpse_delay/1" do
    test "retains hunter corpses for an hour and summoned pets for fifteen seconds", %{pet: pet} do
      assert PetResurrection.corpse_delay(pet) == 3_600_000

      for kind <- [:summon, :guardian, :creature_pet] do
        assert PetResurrection.corpse_delay(%{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: kind}}}) ==
                 15_000
      end
    end
  end

  defp dead_pet(_context) do
    world = WorldRef.open(1)

    pet = %Mob{
      object: %Object{guid: 100, entry: 2960},
      unit: %Unit{
        health: 100,
        max_health: 100,
        power1: 12,
        max_power1: 100,
        power5: 700_000,
        max_power5: 1_050_000,
        pet_number: 123,
        auras: [],
        flags: 0x04000000
      },
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
      internal: %Internal{
        world: world,
        spellbook: %{},
        pet: %Pet{
          owner_guid: 1,
          kind: :hunter,
          profile: :combat,
          training_points: 12,
          loyalty_points: 5_000,
          reaction_state: :passive,
          autocast: MapSet.new([2649])
        }
      }
    }

    pet = pet |> Entity.kill(1_000) |> PetHappiness.on_death(false) |> PetResurrection.prepare_corpse()
    pet = %{pet | internal: %{pet.internal | death_finalized?: true, events: []}}

    context = %CastContext{
      caster_guid: 2,
      caster_level: 60,
      caster_position: {world, 10.0, 20.0, 30.0},
      caster_orientation: 1.5
    }

    %{pet: pet, context: context}
  end
end
