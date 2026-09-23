defmodule ThistleTea.Game.Entity.Logic.AI.BT.CombatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Item
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  defp melee_attack(entity, blackboard, now) do
    target = entity.unit.target
    position = World.target_position(target)
    {x, y, z, _o} = entity.movement_block.position
    {_world, tx, ty, tz} = position
    metadata = Metadata.query(target, [:combat_reach, :alive?]) || %{}

    observation = %Observation{
      guid: target,
      position: position,
      distance: Math.distance({x, y, z}, {tx, ty, tz}),
      metadata: metadata
    }

    perception = Perception.new(now, nil, %{target => observation}, %{mobs: [], players: []})
    Combat.melee_attack_with_context(entity, blackboard, Context.new(now, perception: perception))
  end

  describe "target_valid_same_map?/3" do
    test "retained melee targets must still be detectable" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{target: 2, level: 50, auras: []},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      target = %{level: 50, player?: true, stealthed?: true, stealth_skill: 250}

      for {distance, orientation, metadata, los?, detectable?} <- [
            {5.0, 0.0, target, true, true},
            {5.0, :math.pi(), target, true, false},
            {1.0, :math.pi(), target, true, true},
            {5.0, 0.0, target, false, false},
            {5.0, 0.0, Map.put(target, :undetectable_until, 1_001), true, false},
            {5.0, 0.0, Map.put(target, :stalked_by, [1]), true, true},
            {5.0, 0.0, %{target | stealthed?: false}, true, true}
          ] do
        observation = %Observation{
          guid: 2,
          position: {WorldRef.open(0), distance, 0.0, 0.0},
          distance: distance,
          metadata: metadata,
          line_of_sight?: los?
        }

        perception = Perception.new(1_000, nil, %{2 => observation}, %{mobs: [], players: []})
        context = Context.new(1_000, perception: perception)
        attacker = %{character | movement_block: %{character.movement_block | position: {0.0, 0.0, 0.0, orientation}}}

        assert Combat.target_valid_same_map?(attacker, Blackboard.new(), context) == detectable?
      end
    end
  end

  describe "melee_attack_with_context/3" do
    test "white swings and abilities share bonuses and leave progression to the defender" do
      target_guid = Guid.from_low_guid(:unit, 1, 99_876)
      sword = %ItemTemplate{entry: 99_987_655, class: 2, subclass: 7}
      dagger = %ItemTemplate{entry: 99_987_656, class: 2, subclass: 15}
      :ets.insert(Item, [{sword.entry, sword}, {dagger.entry, dagger}])
      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)

      on_exit(fn ->
        :ets.delete(Item, sword.entry)
        :ets.delete(Item, dagger.entry)
        SpatialHash.remove(:mobs, target_guid)
      end)

      skill = %{value: 1, max: 250, range: :level, always_max?: false}

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          level: 50,
          mainhand_weapon: sword,
          offhand_weapon: dagger,
          min_damage: 10.0,
          max_damage: 10.0,
          min_offhand_damage: 10.0,
          max_offhand_damage: 10.0,
          base_offhand_max_damage: 20.0,
          base_attack_time: 2_000,
          offhand_attack_time: 1_500,
          combat_reach: 1.5,
          auras: [
            %Holder{
              spell: %Spell{id: 20_597},
              caster_guid: 1,
              auras: [%Aura{type: :mod_skill, misc_value: 43, amount: 5}]
            }
          ]
        },
        player: %Player{
          visible_item_16_0: sword.entry,
          visible_item_17_0: dagger.entry,
          skills: %{43 => skill, 173 => skill}
        },
        internal: %Internal{world: WorldRef.open(0), in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}}
      assert {:success, swung, blackboard} = melee_attack(character, blackboard, 1_000)
      assert {:success, swung, _blackboard} = melee_attack(swung, blackboard, 1_200)
      assert swung.player.skills == character.player.skills

      assert [
               %Effects.DeliverAttack{
                 attack: %{caster_attack_skill: 6, weapon_skill_id: 43, dual_wield_penalty?: true}
               },
               %Effects.DeliverAttack{
                 attack: %{caster_attack_skill: 1, weapon_skill_id: 173, offhand?: true, dual_wield_penalty?: true}
               }
             ] = swung.internal.events

      cast = CastContext.from_caster(character, %Spell{id: 78, dmg_class: 2, equipped_item_class: 2}, target_guid)
      assert cast.attack_skill == 6
      assert cast.weapon_skill_id == 43
    end

    test "offhand accuracy follows the live queued attack lifecycle" do
      target_guid = Guid.from_low_guid(:unit, 1, 99_875)
      SpatialHash.update(:mobs, target_guid, 0, 50.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:mobs, target_guid) end)

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          level: 20,
          min_damage: 10.0,
          max_damage: 10.0,
          min_offhand_damage: 5.0,
          max_offhand_damage: 5.0,
          base_offhand_max_damage: 10.0,
          base_attack_time: 2_000,
          offhand_attack_time: 1_500,
          combat_reach: 1.5,
          power2: 1_000
        },
        player: %Player{},
        internal: %Internal{
          world: WorldRef.open(0),
          in_combat: true,
          next_swing_spell: %Spell{id: 78, mana_cost: 150, power_type: 1, dmg_class: 2}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 4_000}}
      assert {:success, distant, blackboard} = melee_attack(character, blackboard, 2_500)
      assert distant.internal.next_swing_spell.id == 78
      assert distant.unit.power2 == 1_000
      refute Enum.any?(distant.internal.events, &match?(%Effects.DeliverSpell{}, &1))
      refute Enum.any?(distant.internal.events, &match?(%Effects.DeliverAttack{}, &1))

      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      distant = %{distant | internal: %{distant.internal | events: []}}

      starved = %{distant | unit: %{distant.unit | power2: 149}}
      assert {:success, rejected, rejected_blackboard} = melee_attack(starved, blackboard, 4_100)
      assert {:success, rejected, _blackboard} = melee_attack(rejected, rejected_blackboard, 4_300)
      assert rejected.internal.next_swing_spell == nil
      assert rejected.unit.power2 == 149
      refute Enum.any?(rejected.internal.events, &match?(%Effects.DeliverSpell{}, &1))

      assert [
               %Effects.SpellCastFailed{spell_id: 78, reason: :no_power},
               %Effects.DeliverAttack{attack: %{dual_wield_penalty?: true}},
               %Effects.DeliverAttack{attack: %{offhand?: true, dual_wield_penalty?: true}}
             ] = rejected.internal.events

      assert {:success, waiting, _} = melee_attack(distant, blackboard, 2_550)
      assert waiting.internal.events == []
      assert {:success, queued, blackboard} = melee_attack(distant, blackboard, 2_600)
      assert queued.internal.next_swing_spell.id == 78
      assert [%Effects.DeliverAttack{attack: %{offhand?: true, dual_wield_penalty?: false}}] = queued.internal.events

      queued = %{queued | internal: %{queued.internal | events: []}}
      assert {:success, consumed, blackboard} = melee_attack(queued, blackboard, 4_100)
      assert {:success, consumed, _blackboard} = melee_attack(consumed, blackboard, 4_300)
      assert consumed.internal.next_swing_spell == nil
      assert consumed.unit.power2 == 850
      assert Enum.any?(consumed.internal.events, &match?(%Effects.DeliverSpell{spell: %Spell{id: 78}}, &1))

      assert Enum.any?(
               consumed.internal.events,
               &match?(%Effects.DeliverAttack{attack: %{offhand?: true, dual_wield_penalty?: true}}, &1)
             )
    end

    test "replaces a disarmed queued weapon ability with an unarmed swing" do
      target_guid = 2
      template = %ItemTemplate{entry: 99_987_654, class: 2, subclass: 15}
      :ets.insert(Item, {template.entry, template})
      on_exit(fn -> :ets.delete(Item, template.entry) end)
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 21.0,
          max_damage: 22.0,
          combat_reach: 1.0,
          power2: 500,
          base_attack_time: 2_000,
          min_offhand_damage: 30.0,
          max_offhand_damage: 40.0,
          offhand_attack_time: 1_500,
          auras: [%Holder{spell: %Spell{id: 676}, caster_guid: 2, auras: [%Aura{type: :mod_disarm}]}],
          offhand_weapon: template
        },
        player: %Player{visible_item_17_0: template.entry, skills: %{162 => %{value: 37}, 173 => %{value: 120}}},
        internal: %Internal{
          world: WorldRef.open(0),
          in_combat: true,
          next_swing_spell: %Spell{id: 78, equipped_item_class: 2, mana_cost: 150, power_type: 1}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}}
      assert {:success, character, blackboard} = melee_attack(character, blackboard, 1_000)
      assert {:success, character, blackboard} = melee_attack(character, blackboard, 1_200)
      assert character.internal.next_swing_spell == nil
      assert character.unit.power2 == 500
      assert blackboard.combat.next_attack_at == 3_000

      assert [
               %Effects.SpellCastFailed{spell_id: 78, reason: :equipped_item},
               %Effects.DeliverAttack{attack: %{caster_attack_skill: 37, min_damage: 21.0, max_damage: 22.0}},
               %Effects.DeliverAttack{
                 attack: %{caster_attack_skill: 120, min_damage: 15.0, max_damage: 20.0, offhand?: true}
               }
             ] = character.internal.events
    end

    test "queues attack delivery events instead of dispatching directly" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 1_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}}

      assert {:success, mob, %Blackboard{}} = melee_attack(mob, blackboard, 1_000)

      assert [
               %Effects.DeliverAttack{
                 target_guid: ^target_guid,
                 attack: %{caster: 1, caster_owner_guid: 1, min_damage: 3, max_damage: 3, damage: 3}
               }
             ] = mob.internal.events
    end

    test "attributes pet swings to the owning player" do
      target_guid = 2
      owner_guid = Guid.from_low_guid(:player, 9)
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      pet = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 1_000
        },
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          in_combat: true,
          creature: %Internal.Creature{damage_school: 2},
          pet: %Internal.Pet{owner_guid: owner_guid, kind: :charmed}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}}

      assert {:success, pet, %Blackboard{}} = melee_attack(pet, blackboard, 1_000)

      assert [%Effects.DeliverAttack{attack: %{caster: 1, caster_owner_guid: ^owner_guid, spell_school_mask: 4}}] =
               pet.internal.events
    end

    test "separates simultaneous dual-wield swings by 200 milliseconds" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 10,
          max_damage: 10,
          min_offhand_damage: 8,
          max_offhand_damage: 8,
          combat_reach: 1.0,
          base_attack_time: 2_000,
          offhand_attack_time: 1_500
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{
        combat: %Blackboard.Combat{
          attack_started: true,
          next_attack_at: 0,
          next_offhand_attack_at: 0
        }
      }

      assert {:success, mob, blackboard} = melee_attack(mob, blackboard, 1_000)

      assert [%Effects.DeliverAttack{attack: %{damage: 10}}] = mob.internal.events
      assert blackboard.combat.next_offhand_attack_at == 1_200
      assert Combat.next_attack_delay(mob, blackboard, 1_000) == 200
      assert {:success, mob, blackboard} = melee_attack(mob, blackboard, 1_200)

      attacks = Enum.filter(mob.internal.events, &is_struct(&1, Effects.DeliverAttack))
      assert length(attacks) == 2
      assert Enum.any?(attacks, &(Map.get(&1.attack, :offhand?) == true and &1.attack.damage == 4))
      assert blackboard.combat.next_attack_at == 3_000
      assert blackboard.combat.next_offhand_attack_at == 2_700
    end

    test "sends queued melee spell go before delivering the attack" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      spell = %Spell{id: 78}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 1_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true, next_swing_spell: spell},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}}

      assert {:success, mob, %Blackboard{}} = melee_attack(mob, blackboard, 1_000)

      assert [
               %Effects.SpellCastResult{spell_id: 78},
               %Effects.SpellGo{spell_id: 78, hit_guids: [^target_guid]},
               %Effects.DeliverSpell{target_guid: ^target_guid, spell: %Spell{id: 78}}
             ] = mob.internal.events

      assert mob.internal.next_swing_spell == nil
    end

    test "resolves queued chain weapon attacks against nearby enemies" do
      player_guid = Guid.from_low_guid(:player, 10)
      primary_guid = Guid.from_low_guid(:mob, 1, 10)
      secondary_guid = Guid.from_low_guid(:mob, 1, 11)

      player_faction = %FactionTemplate{
        id: 1,
        faction: 1,
        flags: 72,
        faction_group: 3,
        friend_group: 2,
        enemy_group: 12
      }

      mob_faction = %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}

      Enum.each([{player_guid, :players, 0.0}, {primary_guid, :mobs, 1.0}, {secondary_guid, :mobs, 2.0}], fn
        {guid, table, x} -> SpatialHash.update(table, guid, 0, x, 0.0, 0.0)
      end)

      Metadata.put(player_guid, %{alive?: true, faction_template: player_faction, unit_flags: 0})

      Enum.each([primary_guid, secondary_guid], fn guid ->
        Metadata.put(guid, %{
          alive?: true,
          faction_template: mob_faction,
          faction_can_have_reputation?: false,
          unit_flags: 0
        })
      end)

      on_exit(fn ->
        SpatialHash.remove(:players, player_guid)
        SpatialHash.remove(:mobs, primary_guid)
        SpatialHash.remove(:mobs, secondary_guid)
        Enum.each([player_guid, primary_guid, secondary_guid], &Metadata.delete/1)
      end)

      cleave = %Spell{
        id: 845,
        attributes: MapSet.new([:on_next_swing]),
        effects: [%Spell.Effect{type: :weapon_damage_noschool, implicit_target_a: :target_enemy, chain_targets: 2}]
      }

      character = %Character{
        object: %Object{guid: player_guid},
        player: %Player{},
        unit: %Unit{target: primary_guid, min_damage: 3, max_damage: 3, combat_reach: 1.0, base_attack_time: 1_000},
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          in_combat: true,
          next_swing_spell: cleave
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert {:success, character, %Blackboard{}} =
               melee_attack(
                 character,
                 %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}},
                 1_000
               )

      assert %Effects.SpellGo{hit_guids: [^primary_guid, ^secondary_guid]} =
               Enum.find(character.internal.events, &is_struct(&1, Effects.SpellGo))

      assert [^primary_guid, ^secondary_guid] =
               for(%Effects.DeliverSpell{target_guid: guid} <- character.internal.events, do: guid)
    end

    test "swings immediately on fresh aggro when already in reach" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 2_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: false, next_attack_at: 0}}

      assert {:success, mob,
              %Blackboard{
                combat: %Blackboard.Combat{attack_started: true, next_attack_at: 3_000}
              }} =
               melee_attack(mob, blackboard, 1_000)

      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.DeliverAttack))
    end

    test "retries shortly instead of arming a full swing timer when out of reach on fresh aggro" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 50.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 2_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: false, next_attack_at: 0}}

      assert {:success, mob,
              %Blackboard{
                combat: %Blackboard.Combat{attack_started: true, next_attack_at: 1_100}
              }} =
               melee_attack(mob, blackboard, 1_000)

      refute Enum.any?(mob.internal.events, &is_struct(&1, Effects.DeliverAttack))
    end

    test "notifies a player once per continuous out-of-range swing error" do
      player_guid = Guid.from_low_guid(:player, 1)
      target_guid = Guid.from_low_guid(:mob, 1, 1)
      SpatialHash.update(:mobs, target_guid, 0, 50.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:mobs, target_guid) end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 2_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: false, next_attack_at: 0}}

      assert {:success, character, blackboard} = melee_attack(character, blackboard, 1_000)
      assert Enum.count(character.internal.events, &is_struct(&1, Effects.AttackNotInRange)) == 1
      assert blackboard.combat.last_swing_error == :not_in_range

      character = %{character | internal: %{character.internal | events: []}}

      assert {:success, character, blackboard} = melee_attack(character, blackboard, 1_100)
      refute Enum.any?(character.internal.events, &is_struct(&1, Effects.AttackNotInRange))
      assert blackboard.combat.next_attack_at == 1_200

      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)

      assert {:success, character, blackboard} = melee_attack(character, blackboard, 1_200)
      assert Enum.any?(character.internal.events, &is_struct(&1, Effects.DeliverAttack))
      assert blackboard.combat.last_swing_error == nil

      character = %{character | internal: %{character.internal | events: []}}
      SpatialHash.update(:mobs, target_guid, 0, 50.0, 0.0, 0.0)

      assert {:success, character, _blackboard} = melee_attack(character, blackboard, 3_200)
      assert Enum.count(character.internal.events, &is_struct(&1, Effects.AttackNotInRange)) == 1
    end

    test "grants no rage at swing time since rage flows from resolved outcomes" do
      player_guid = Guid.from_low_guid(:player, 1)
      target_guid = Guid.from_low_guid(:mob, 1, 1)

      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:mobs, target_guid) end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{
          target: target_guid,
          min_damage: 10,
          max_damage: 10,
          combat_reach: 1.0,
          base_attack_time: 1_000,
          power_type: 1,
          power2: 0,
          max_power2: 1_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true, next_attack_at: 0}}

      assert {:success, character, %Blackboard{}} = melee_attack(character, blackboard, 1_000)

      assert character.unit.power2 == 0

      assert [
               %Effects.DeliverAttack{target_guid: ^target_guid, attack: %{damage: 10}}
             ] = Enum.filter(character.internal.events, &is_struct(&1, Effects.DeliverAttack))
    end
  end

  describe "wait_for_next_attack/3" do
    test "returns running delay from explicit time" do
      blackboard = %Blackboard{combat: %Blackboard.Combat{next_attack_at: 1_250}}
      state = %Mob{}

      assert {{:running, 250}, ^state, ^blackboard} = Combat.wait_for_next_attack(state, blackboard, 1_000)
    end
  end

  describe "in_combat?/2" do
    test "a player qualifies on auto-attack intent even before the combat flag is set" do
      character = %Character{unit: %Unit{target: 2}, internal: %Internal{in_combat: false}}

      assert Combat.in_combat?(
               character,
               %Blackboard{combat: %Blackboard.Combat{auto_attacking: true}}
             )
    end

    test "a player without auto-attack intent does not qualify even while flagged in combat" do
      character = %Character{unit: %Unit{target: 2}, internal: %Internal{in_combat: true}}

      refute Combat.in_combat?(
               character,
               %Blackboard{combat: %Blackboard.Combat{auto_attacking: false}}
             )
    end

    test "a mob still requires the in-combat flag, not just intent" do
      not_engaged = %Mob{unit: %Unit{target: 2}, internal: %Internal{in_combat: false}}
      engaged = %Mob{unit: %Unit{target: 2}, internal: %Internal{in_combat: true}}

      refute Combat.in_combat?(
               not_engaged,
               %Blackboard{combat: %Blackboard.Combat{auto_attacking: true}}
             )

      assert Combat.in_combat?(engaged, %Blackboard{})
    end
  end
end
