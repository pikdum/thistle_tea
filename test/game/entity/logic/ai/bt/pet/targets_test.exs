defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet.TargetsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet.Autocast
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "try_cast/4" do
    test "Fire Shield automatically protects the owner instead of wasting a self cast", context do
      Metadata.update(context.owner, %{attacker_count: 1})
      Metadata.update(context.outsider, %{attacker_count: 1})
      pet = with_spell(context.pet, shield())
      assert cast_target(pet, AIEnvironment.context(pet, 1_000)) == context.owner
    end

    test "shares buffs with the current raid subgroup and preserves old observations", context do
      group(context.owner, [context.ally, context.outsider])
      {:ok, _} = PartySystem.convert_raid(context.owner)
      {:ok, _} = PartySystem.change_subgroup(context.owner, context.outsider, 1)
      Metadata.update(context.ally, %{attacker_count: 1})
      Metadata.update(context.outsider, %{attacker_count: 1})
      pet = with_spell(context.pet, shield())
      before = AIEnvironment.context(pet, 1_000)
      assert context.ally in before.pet_allies
      refute context.outsider in before.pet_allies
      assert cast_target(pet, before) == context.ally

      {:ok, _} = PartySystem.change_subgroup(context.owner, context.ally, 1)
      after_change = AIEnvironment.context(pet, 1_000)
      assert cast_target(pet, after_change) == nil
      assert cast_target(pet, before) == context.ally
    end

    test "skips obstructed, dead, distant, absent and foreign-world allies", context do
      group(context.owner, [context.ally])
      Metadata.update(context.owner, %{attacker_count: 1})
      Metadata.update(context.ally, %{attacker_count: 1})
      pet = with_spell(context.pet, shield())
      snapshot = AIEnvironment.context(pet, 1_000)
      original = snapshot.perception.entities[context.owner]

      for observation <- [
            %{original | line_of_sight?: false},
            %{original | metadata: %{original.metadata | alive?: false}},
            %{original | position: {pet.internal.world, 100.0, 0.0, 0.0}},
            %{original | position: nil, metadata: nil},
            %{original | position: {WorldRef.instance(999, 1), 5.0, 0.0, 0.0}}
          ] do
        perception = %{
          snapshot.perception
          | entities: Map.put(snapshot.perception.entities, context.owner, observation)
        }

        assert cast_target(pet, %{snapshot | perception: perception}) == context.ally
      end
    end

    test "skips the owner's existing aura and shields another attacked party member", context do
      group(context.owner, [context.ally])
      Metadata.update(context.owner, %{attacker_count: 1, aura_effects: MapSet.new([{1, 0}])})
      Metadata.update(context.ally, %{attacker_count: 1})
      pet = with_spell(context.pet, shield())
      assert cast_target(pet, AIEnvironment.context(pet, 1_000)) == context.ally
    end

    test "Devour Magic prefers an enemy buff and falls back to an allied debuff", context do
      Metadata.update(context.owner, %{victim_guid: context.enemy, dispel_options: MapSet.new([{1, :negative}])})
      Metadata.update(context.enemy, %{dispel_options: MapSet.new([{1, :positive}])})
      pet = with_spell(context.pet, devour())
      assert cast_target(pet, AIEnvironment.context(pet, 1_000)) == context.enemy
      Metadata.update(context.enemy, %{dispel_options: MapSet.new([{1, :negative}])})
      assert cast_target(pet, AIEnvironment.context(pet, 1_000)) == context.owner
      Metadata.update(context.owner, %{dispel_options: MapSet.new()})
      snapshot = AIEnvironment.context(pet, 1_000)
      assert {:failure, unchanged, _} = Spells.try_cast(pet, Blackboard.new(), snapshot, self_only?: true)
      assert unchanged.internal.events == []
      assert unchanged.internal.cooldowns == pet.internal.cooldowns
      assert unchanged.unit.power1 == pet.unit.power1
    end

    test "Devour Magic observes an attacker even without a pet or owner victim", context do
      Metadata.update(context.enemy, %{victim_guid: context.owner, dispel_options: MapSet.new([{1, :positive}])})
      pet = with_spell(context.pet, devour())
      snapshot = AIEnvironment.context(pet, 1_000)
      assert cast_target(pet, snapshot) == context.enemy
      assert snapshot.perception.entities[context.enemy].distance == 25.0
    end

    test "manual dispels use the same observed aura polarity", context do
      Metadata.update(context.ally, %{dispel_options: MapSet.new([{1, :negative}])})
      pet = with_spell(context.pet, devour())
      snapshot = AIEnvironment.context(pet, 1_000)
      [entry] = pet.internal.creature.spells
      assert {:ok, {casted, _}} = Spells.attempt_commanded_cast(pet, Blackboard.new(), entry, context.ally, snapshot)
      assert Target.unit_guid(casted.internal.casting.targets) == context.ally
    end
  end

  describe "candidates/3" do
    test "self, owner and area spells only consider their actual recipients", context do
      pet = with_spell(context.pet, shield())
      pet = %{pet | unit: %{pet.unit | target: context.enemy}}
      snapshot = AIEnvironment.context(pet, 1_000)

      for {implicit, expected} <- [caster: [pet.object.guid], caster_master: [context.owner]] do
        spell = %Spell{effects: [%Effect{type: :apply_aura, implicit_target_a: implicit}]}
        assert Autocast.candidates(pet, spell, snapshot) == expected
      end

      spell = %Spell{effects: [%Effect{type: :apply_aura, implicit_target_a: :party_around_caster, radius_yards: 10.0}]}
      assert MapSet.new(Autocast.candidates(pet, spell, snapshot)) == MapSet.new([pet.object.guid, context.owner])

      spell = %Spell{
        effects: [%Effect{type: :school_damage, implicit_target_a: :aoe_enemy_at_caster, radius_yards: 10.0}]
      }

      assert Autocast.candidates(pet, spell, snapshot) == []
    end
  end

  defp cast_target(pet, snapshot) do
    case Spells.try_cast(pet, Blackboard.new(), snapshot, self_only?: true) do
      {{:running, _, :casting}, casted, _} ->
        Target.unit_guid(casted.internal.casting.targets)

      {:failure, unchanged, _} ->
        assert(unchanged.internal.events == [])
        nil
    end
  end

  defp shield do
    %Spell{
      id: 1,
      cast_time_ms: 1_000,
      range_yards: 30.0,
      mana_cost: 10,
      power_type: 0,
      spell_family: 5,
      family_flags_0: 0x00800000,
      spell_visual: 289,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :damage_shield, implicit_target_a: :party_member}]
    }
  end

  defp devour do
    %Spell{
      id: 1,
      cast_time_ms: 1_000,
      range_yards: 30.0,
      mana_cost: 10,
      power_type: 0,
      effects: [%Effect{index: 0, type: :dispel, misc_value: 1, implicit_target_a: :any_unit}]
    }
  end

  defp with_spell(pet, spell) do
    spellbook = %{spell.id => spell}
    creature = %Internal.Creature{spells: PetTraining.action_spells(spellbook)}
    %{pet | internal: %{pet.internal | spellbook: spellbook, creature: creature}}
  end

  defp group(owner, members) do
    for member <- members do
      :ok = PartySystem.invite(owner, "Owner", member)
      {:ok, _} = PartySystem.accept(member, "Ally")
    end
  end

  defp entities(_context) do
    world = WorldRef.open(999)
    owner = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    ally = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    outsider = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    enemy = Guid.runtime(:mob, 2)
    guid = Guid.runtime(:pet, 416)
    friendly = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
    hostile = %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}

    for {type, actor, distance, faction} <- [
          {:players, owner, 5.0, friendly},
          {:players, ally, 25.0, friendly},
          {:players, outsider, 10.0, friendly},
          {:mobs, enemy, 25.0, hostile},
          {:mobs, guid, 0.0, friendly}
        ] do
      SpatialHash.update(type, actor, world, distance, 0.0, 0.0)
      Metadata.put(actor, %{alive?: true, level: 60, faction_template: faction, unit_flags: 0, attacker_count: 0})

      on_exit(fn ->
        SpatialHash.remove(type, actor)
        Metadata.delete(actor)
        PartySystem.leave(actor)
      end)
    end

    Metadata.update(guid, %{owner_guid: owner})

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 60, auras: [], target: 0},
      internal: %Internal{
        world: world,
        in_combat: false,
        pet: %Internal.Pet{kind: :summon, owner_guid: owner, autocast: MapSet.new([1])}
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{pet: pet, owner: owner, ally: ally, outsider: outsider, enemy: enemy}
  end
end
