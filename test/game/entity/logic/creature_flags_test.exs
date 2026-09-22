defmodule ThistleTea.Game.Entity.Logic.CreatureFlagsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ProcDamage
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.EffectImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:creature]

  describe "Mob.build/1" do
    test "projects template target restrictions and swimming", %{creature: creature} do
      mob = build(creature, 0x10400260)
      assert mob.unit.flags == 0x02009300
      assert mob.internal.spawn.unit.flags == mob.unit.flags
      assert mob.internal.creature.static_flags == 0x10400260
      refute CreatureFlags.has?(mob, :no_melee)
      assert build(creature, 0).unit.flags == 0
    end

    test "player and NPC immunity distinguish controlled creatures", %{creature: creature} do
      player = %{guid: 1, alive?: true, unit_flags: 0}
      npc = %{player | guid: Guid.from_low_guid(:mob, 3, 3)}
      pet = Map.put(npc, :owner_guid, 1)
      ordinary = build(creature, 0)
      player_immune = build(creature, 0x20)
      npc_immune = build(creature, 0x40)
      unselectable = build(creature, 0x200)

      assert Hostility.valid_attack_target?(player, ordinary)
      refute Hostility.valid_attack_target?(player, player_immune)
      refute Hostility.valid_attack_target?(pet, player_immune)
      assert Hostility.valid_attack_target?(player, npc_immune)
      assert Hostility.valid_attack_target?(pet, npc_immune)
      refute Hostility.valid_attack_target?(npc, npc_immune)
      refute Hostility.valid_attack_target?(player, unselectable)
    end
  end

  describe "Core.take_damage/4" do
    test "unkillable creatures survive repeated lethal damage", %{creature: creature} do
      mob = build(creature, 8)
      mob = Core.take_damage(mob, 1_000, 1_000, source: 1)
      assert mob.unit.health == 1
      refute Core.dead?(mob)
      refute mob.internal.death_finalized?
      assert Core.take_damage(mob, 1_000, 2_000, source: 1).unit.health == 1
      assert Core.take_damage(build(creature, 0), 1_000, 1_000).unit.health == 0
    end

    test "damage over time respects the same floor", %{creature: creature} do
      mob = build(creature, 8)

      spell = %Spell{
        id: 99,
        duration_ms: 3_000,
        school: :physical,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 150, amplitude_ms: 1_000}]
      }

      {mob, _events} = Aura.apply_spell(mob, 1, 20, spell, 0)
      {mob, _events} = Aura.tick(mob, 1_000)
      assert mob.unit.health == 1
      {mob, _events} = Aura.tick(mob, 2_000)
      assert mob.unit.health == 1
      refute Core.dead?(mob)
    end

    test "scripts can override the threshold and scripted death still works", %{creature: creature} do
      mob = build(creature, 8)
      mob = %{mob | internal: %{mob.internal | invincibility_health_threshold: 20}}
      assert Core.take_damage(mob, 1_000, 1_000).unit.health == 20
      mob = %{mob | internal: %{mob.internal | invincibility_health_threshold: 0}}
      assert Core.take_damage(mob, 1_000, 1_000).unit.health == 0
      restored = mob |> Core.kill(1_000) |> Mob.respawn()
      assert restored.internal.invincibility_health_threshold == 1
      dead = Core.kill(build(creature, 8), 1_000)
      assert dead.unit.health == 0
      respawned = Mob.respawn(dead)
      assert respawned.unit.health == 100
      assert Core.take_damage(respawned, 1_000, 2_000).unit.health == 1
    end
  end

  describe "SpellEffect.receive/4" do
    test "sessile creatures reject movement controls and emit immune feedback", %{creature: creature} do
      mob = build(creature, 0x100)

      for aura <- [:mod_fear, :mod_root, :mod_confuse] do
        spell = control(aura)
        {updated, events} = SpellEffect.receive(mob, 1, spell, 1_000)
        refute Aura.has_aura?(updated, aura)
        assert [%Effects.SpellLogMiss{reason: :immune}] = events
        assert updated.internal.navigation_intents == []
      end

      for type <- [:knockback, :distract, :pull] do
        effect = %Effect{type: type}
        assert EffectImmunity.blocked?(mob, %Spell{id: 99, effects: [effect]}, effect)
      end
    end

    test "sessile immunity preserves damage and unrelated controls", %{creature: creature} do
      mob = build(creature, 0x100)
      root = control(:mod_root)
      spell = %{root | effects: [%Effect{index: 1, type: :school_damage, base_points: 10} | root.effects]}
      {updated, events} = SpellEffect.receive(mob, 1, spell, 1_000)
      assert updated.unit.health == 90
      refute Aura.has_aura?(updated, :mod_root)
      assert Enum.any?(events, &is_struct(&1, Effects.SpellDamage))
      {stunned, _events} = SpellEffect.receive(mob, 1, control(:mod_stun), 1_000)
      assert Aura.has_aura?(stunned, :mod_stun)
      bypass = %{root | attributes: MapSet.new([:ignore_caster_and_target_restrictions])}
      {rooted, _events} = SpellEffect.receive(mob, 1, bypass, 1_000)
      assert Aura.has_aura?(rooted, :mod_root)
    end
  end

  describe "BT.tick/3" do
    test "combat dummies neither attack nor chase and do not spin", %{creature: creature} do
      mob = creature |> build(0x100100) |> engage()

      for distance <- [0.1, 20.0] do
        {{:running, delay, _reason}, updated} = BT.tick(MobBT.tree(), mob, context(distance))
        assert delay > 0
        assert updated.internal.navigation_intents == []
        refute Enum.any?(updated.internal.events, &is_struct(&1, Effects.DeliverAttack))
        refute updated.internal.blackboard.combat.attack_started
      end
    end

    test "sessile creatures can still melee in range", %{creature: creature} do
      mob = creature |> build(0x100) |> engage()
      {_status, updated} = BT.tick(MobBT.tree(), mob, context(1.0))
      assert Enum.any?(updated.internal.events, &is_struct(&1, Effects.DeliverAttack))
      assert updated.internal.navigation_intents == []
    end

    test "scripts override defaults until combat resets", %{creature: creature} do
      mob = creature |> build(0x100100) |> engage()

      steps = [
        %ScriptStep{command: :set_melee_attack, datalong: 1},
        %ScriptStep{command: :set_combat_movement, datalong: 1}
      ]

      {mob, blackboard} = Script.run(mob, mob.internal.blackboard, steps, 1, 1_000)
      assert Blackboard.melee_enabled?(blackboard, mob)
      assert Blackboard.combat_movement?(blackboard, mob)
      mob = %{mob | internal: %{mob.internal | blackboard: blackboard}}
      {_status, attacking} = BT.tick(MobBT.tree(), mob, context(1.0))
      assert Enum.any?(attacking.internal.events, &is_struct(&1, Effects.DeliverAttack))
      {_status, chasing} = BT.tick(MobBT.tree(), mob, context(20.0))
      assert chasing.internal.navigation_intents != []

      %Engagement.Result{entity: reset} = Engagement.leave(mob, :evade)
      refute Blackboard.melee_enabled?(reset.internal.blackboard, reset)
      refute Blackboard.combat_movement?(reset.internal.blackboard, reset)
      respawned = Mob.respawn(Core.kill(mob, 2_000))
      refute Blackboard.melee_enabled?(Blackboard.new(), respawned)
      refute Blackboard.combat_movement?(Blackboard.new(), respawned)
    end

    test "sessile evasion cleans combat without moving home", %{creature: creature} do
      mob = creature |> build(0x100108) |> engage() |> Core.take_damage(99, 500)
      mob = %{mob | movement_block: %{mob.movement_block | position: {10.0, 0.0, 0.0, 0.0}}}
      reset = MobBT.drop_threat(mob, 1, context(20.0))
      assert reset.unit.health == 100
      refute reset.internal.in_combat
      assert reset.internal.threat == %{}
      assert reset.internal.navigation_intents == []
      assert reset.movement_block.position == mob.movement_block.position
      {_status, arrived} = BT.tick(MobBT.tree(), reset, context(20.0))
      assert arrived.internal.blackboard.navigation.move_target == nil
      assert arrived.internal.navigation_intents == []
    end
  end

  describe "Skills.defense_value/2" do
    test "no-defense creatures use zero skill in the melee table", %{creature: creature} do
      normal = build(creature, 0)
      defenseless = build(creature, 0x4000)
      assert Skills.defense_value(normal) == 100
      assert Skills.defense_value(defenseless) == 0
      attack = %{caster: 1, caster_level: 20, caster_player?: true, crit_chance: 5.0}
      assert AttackTable.resolve(normal, attack, 10, roll: 0).outcome == :miss
      refute AttackTable.resolve(defenseless, attack, 10, roll: 0).outcome == :miss
    end
  end

  describe "SpellResist.magic_hit?/4" do
    test "no-spell-defense bypasses level and mechanic misses", %{creature: creature} do
      opts = [roll: 9_999, hit_bonus: -100, mechanic_resistance: 100]
      refute SpellResist.magic_hit?(1, 60, false, opts)
      assert SpellResist.magic_hit?(1, 60, false, Keyword.put(opts, :no_spell_defense?, true))
      target = %{level: 60, mechanic_resistance: [{5, 100}], no_spell_defense?: true}
      spell = %{control(:mod_fear) | dmg_class: 1, mechanic: 5}
      assert ProcDamage.hit?(build(creature, 0), spell, target, false, roll: 9_999)
      refute ProcDamage.hit?(build(creature, 0), spell, %{target | no_spell_defense?: false}, false, roll: 9_999)
    end
  end

  defp control(aura) do
    %Spell{
      id: 99,
      school: :physical,
      duration_ms: 10_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, implicit_target_a: :target_enemy}]
    }
  end

  defp engage(mob) do
    %Engagement.Result{entity: mob} = Engagement.enter(mob, 1, 0, selection: :target)
    %{mob | internal: %{mob.internal | events: []}}
  end

  defp context(distance) do
    world = WorldRef.open(0)

    observation = %Observation{
      guid: 1,
      position: {world, distance, 0.0, 0.0},
      grounded_position: {world, distance, 0.0, 0.0},
      metadata: %{alive?: true}
    }

    Context.new(1_000, perception: Perception.new(1_000, nil, %{1 => observation}, %{}))
  end

  defp build(creature, flags) do
    Mob.build(%{creature | creature_template: %{creature.creature_template | creature_type_flags: flags}})
  end

  defp creature(_context) do
    %{
      creature: %Mangos.Creature{
        guid: 1,
        id: 1921,
        modelid: 3,
        curhealth: 100,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        orientation: 0.0,
        map: 0,
        creature_movement: [],
        equip_items: [nil, nil, nil],
        creature_template: %Mangos.CreatureTemplate{
          entry: 1921,
          name: "Combat Dummy",
          min_level: 20,
          max_level: 20,
          scale: 1.0,
          extra_flags: 2,
          melee_base_attack_time: 2_000,
          min_melee_dmg: 1.0,
          max_melee_dmg: 2.0
        }
      }
    }
  end
end
