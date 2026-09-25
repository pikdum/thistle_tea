defmodule ThistleTea.Game.Entity.Server.Mob.PetCommandsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Server.Mob.PetCommands
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:build_pet]

  describe "stop_attack/2" do
    test "admits current pet and possession controllers", ctx do
      assert PetCommands.stop_attack(ctx.pet, ctx.owner).unit.target == 0
      possessed = %{ctx.pet | internal: %{ctx.pet.internal | pet: %{ctx.pet.internal.pet | possessed?: true}}}
      assert PetCommands.stop_attack(possessed, ctx.owner).unit.target == 0
    end

    test "ignores dead pets and stale, replaced, or distant controllers", ctx do
      assert PetCommands.stop_attack(ctx.pet, ctx.owner + 1) == ctx.pet
      dead = %{ctx.pet | unit: %{ctx.pet.unit | health: 0}}
      assert PetCommands.stop_attack(dead, ctx.owner) == dead
      Metadata.update(ctx.owner, %{controlled_guid: ctx.guid + 1})
      assert PetCommands.stop_attack(ctx.pet, ctx.owner) == ctx.pet
      Metadata.update(ctx.owner, %{controlled_guid: ctx.guid})
      SpatialHash.remove(:players, ctx.owner)
      assert PetCommands.stop_attack(ctx.pet, ctx.owner) == ctx.pet
    end
  end

  describe "cancel_aura/3" do
    test "removes external buffs through stat and aura projection while preserving other schedules", ctx do
      armor = %Spell{
        id: 100,
        duration_ms: 60_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_resistance, misc_value: 1, base_points: 29}
        ]
      }

      poison = %Spell{
        id: 200,
        duration_ms: 60_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :periodic_damage, amplitude_ms: 2_000, base_points: 3}
        ]
      }

      now = Time.now()
      {pet, _} = Aura.apply_spell(ctx.pet, ctx.owner, 50, armor, now)
      {pet, _} = Aura.apply_spell(pet, ctx.owner + 1, 50, poison, now)
      assert pet.unit.normal_resistance == 36
      other = Enum.find(pet.unit.auras, &(&1.spell.id == 200))
      pet = %{pet | internal: %{pet.internal | broadcast_update?: false}}
      cancelled = PetCommands.cancel_aura(pet, ctx.owner, 100)
      assert cancelled.unit.normal_resistance == 7
      assert cancelled.unit.auras == [other]
      assert cancelled.internal.broadcast_update?
      refute Aura.has_spell?(cancelled, 100)
      assert PetCommands.cancel_aura(cancelled, ctx.owner, 999) == cancelled
    end

    test "rejects stale owners and remote possession and reports a dead pet", ctx do
      assert PetCommands.cancel_aura(ctx.pet, ctx.owner + 1, 100) == ctx.pet
      possessed = %{ctx.pet | internal: %{ctx.pet.internal | pet: %{ctx.pet.internal.pet | possessed?: true}}}
      assert PetCommands.cancel_aura(possessed, ctx.owner, 100) == possessed
      dead = %{ctx.pet | unit: %{ctx.pet.unit | health: 0}}
      assert PetCommands.cancel_aura(dead, ctx.owner, 100) == dead
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetActionFeedback{feedback: :pet_dead}}}
      Metadata.update(ctx.owner, %{controlled_guid: ctx.guid + 1})
      assert PetCommands.cancel_aura(dead, ctx.owner, 100) == dead
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetActionFeedback{}}}, 0
    end
  end

  defp build_pet(_context) do
    owner = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
    world = WorldRef.open(0)
    Entity.register(owner)
    Metadata.put(owner, %{controlled_guid: guid})
    SpatialHash.update(:players, owner, world, 0.0, 0.0, 0.0)

    on_exit(fn ->
      Entity.unregister(owner)
      Metadata.delete(owner)
      SpatialHash.remove(:players, owner)
    end)

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, base_normal_resistance: 7, target: 123, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, pet: %Pet{owner_guid: owner}, creature: %Creature{}, spellbook: %{}}
    }

    %{pet: pet, owner: owner, guid: guid}
  end
end
