defmodule ThistleTea.Game.Entity.Server.Mob.PetCastingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob.PetCasting
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:build_pet]

  describe "cast/4" do
    test "starts known spells and preserves the current cast on a second request", ctx do
      targets = Target.self(ctx.guid)
      cast = PetCasting.cast(ctx.pet, ctx.owner, ctx.spell.id, targets)
      assert cast.internal.casting.targets == targets
      assert cast.internal.casting.spell == ctx.spell
      assert PetCasting.cast(cast, ctx.owner, ctx.spell.id, targets) == cast
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetCastFailed{reason: :spell_in_progress}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgClearCooldown{target_guid: guid}}}
      assert guid == ctx.guid
    end

    test "rejects stale ownership, replaced pets, and world changes without casting", ctx do
      targets = Target.self(ctx.guid)
      assert PetCasting.cast(ctx.pet, ctx.owner + 1, ctx.spell.id, targets) == ctx.pet
      Metadata.update(ctx.owner, %{controlled_guid: ctx.guid + 1})
      assert PetCasting.cast(ctx.pet, ctx.owner, ctx.spell.id, targets) == ctx.pet
      Metadata.update(ctx.owner, %{controlled_guid: ctx.guid})
      SpatialHash.update(:players, ctx.owner, WorldRef.instance(0, 123), 0.0, 0.0, 0.0)
      assert PetCasting.cast(ctx.pet, ctx.owner, ctx.spell.id, targets) == ctx.pet
      refute_receive {:"$gen_cast", {:send_packet, _}}, 0
    end

    test "does not cast unknown or passive spells", ctx do
      targets = Target.self(ctx.guid)
      assert PetCasting.cast(ctx.pet, ctx.owner, ctx.spell.id + 1, targets) == ctx.pet
      passive = %{ctx.spell | attributes: MapSet.new([:passive])}
      pet = %{ctx.pet | internal: %{ctx.pet.internal | spellbook: %{passive.id => passive}}}
      assert PetCasting.cast(pet, ctx.owner, passive.id, targets) == pet
    end

    test "rejects a dead controller and reports power failure without consuming resources", ctx do
      targets = Target.self(ctx.guid)
      Metadata.update(ctx.owner, %{alive?: false})
      assert PetCasting.cast(ctx.pet, ctx.owner, ctx.spell.id, targets) == ctx.pet
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetCastFailed{reason: :caster_dead}}}
      Metadata.update(ctx.owner, %{alive?: true})
      pet = %{ctx.pet | unit: %{ctx.pet.unit | power1: 0}}
      assert PetCasting.cast(pet, ctx.owner, ctx.spell.id, targets) == pet
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetCastFailed{reason: :no_power}}}
    end

    test "retains a real cooldown when sending a cast failure", ctx do
      pet = Cooldowns.start(ctx.pet, ctx.spell, Time.now())
      assert PetCasting.cast(pet, ctx.owner, ctx.spell.id, Target.self(ctx.guid)) == pet
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetCastFailed{reason: :not_ready}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgClearCooldown{}}}, 0
    end
  end

  describe "Spells.attempt_commanded_cast/6" do
    test "retains ground targets through preparation and delivery, spending power once", ctx do
      spell = %{ctx.spell | effects: [%Effect{index: 0, type: :school_damage, implicit_target_a: :aoe_enemy_at_dest}]}
      pet = %{ctx.pet | internal: %{ctx.pet.internal | spellbook: %{spell.id => spell}}}
      targets = Target.at({12.0, -5.0, 1.0})
      entry = %CreatureSpell{spell_id: spell.id}

      assert {:ok, {cast, _}} =
               Spells.attempt_commanded_cast(pet, Blackboard.new(), entry, targets, Context.new(0),
                 destination_los?: true
               )

      assert cast.internal.casting.targets == targets
      finished = Casting.complete(cast, 3_000)
      assert finished.unit.power1 == 80
      assert Cooldowns.on_cooldown?(finished, spell, 3_000)
      assert Enum.any?(finished.internal.events, &match?(%Effects.SpellGo{targets: ^targets}, &1))

      assert {:error, :line_of_sight} =
               Spells.attempt_commanded_cast(pet, Blackboard.new(), entry, targets, Context.new(0),
                 destination_los?: false
               )
    end
  end

  defp build_pet(_context) do
    owner = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
    world = WorldRef.open(0)
    Entity.register(owner)
    Metadata.put(owner, %{alive?: true, controlled_guid: guid})
    SpatialHash.update(:players, owner, world, 0.0, 0.0, 0.0)

    on_exit(fn ->
      Entity.unregister(owner)
      Metadata.delete(owner)
      SpatialHash.remove(:players, owner)
    end)

    spell = %Spell{
      id: 123,
      cast_time_ms: 3_000,
      mana_cost: 20,
      power_type: 0,
      range_yards: 30.0,
      recovery_time_ms: 5_000
    }

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: world,
        pet: %Pet{owner_guid: owner},
        creature: %Creature{},
        spellbook: %{spell.id => spell}
      }
    }

    %{pet: pet, owner: owner, guid: guid, spell: spell}
  end
end
