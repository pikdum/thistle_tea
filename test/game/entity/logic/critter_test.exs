defmodule ThistleTea.Game.Entity.Logic.CritterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Critter
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:mob]

  describe "Core.take_damage/4" do
    test "surviving damage starts escape without a victim or retaliation", %{mob: mob} do
      mob = Core.take_damage(mob, 3, 1_000, source: 1)
      assert mob.unit.health == 17
      assert mob.unit.target == 0
      assert mob.internal.in_combat
      assert mob.internal.blackboard.critter.escape_at == 31_000
      assert mob.internal.blackboard.combat.flee_until == 31_000
      assert mob.internal.blackboard.combat.flee_from == 1
      assert Bitwise.band(mob.unit.flags, 0x800000) != 0
      refute Enum.any?(mob.internal.events, &is_struct(&1, Effects.AttackerGained))
    end

    test "later hits extend combat without replacing an active flee", %{mob: mob} do
      mob = mob |> Core.take_damage(1, 1_000, source: 1) |> Core.take_damage(1, 5_000, source: 2)
      assert mob.internal.blackboard.critter.escape_at == 35_000
      assert mob.internal.blackboard.combat.flee_until == 31_000
      assert mob.internal.blackboard.combat.flee_from == 1
    end

    test "lethal hits clear fleeing and retain corpse ownership", %{mob: mob} do
      mob = mob |> Engagement.claim(%Tap{player: 1}) |> Core.take_damage(1, 1_000, source: 1)
      dead = Core.take_damage(mob, 100, 2_000, source: 1)
      assert dead.unit.health == 0
      assert dead.internal.blackboard.critter == nil
      assert dead.internal.blackboard.combat.flee_until == nil
      assert dead.internal.loot.tapped_by == %Tap{player: 1}
      assert dead.internal.threat == %{}
      refute dead.internal.in_combat
      assert Bitwise.band(dead.unit.flags, 0x800000) == 0
      assert dead.movement_block.spline_nodes == []
    end

    test "ordinary creatures and companions keep their own behavior", %{mob: mob} do
      ordinary = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | critter?: false}}}
      companion = %{mob | internal: %{mob.internal | pet: %Pet{owner_guid: 1}}}

      for entity <- [ordinary, companion] do
        result = Core.take_damage(entity, 1, 1_000, source: 1)
        assert result.internal.blackboard.critter == nil
      end

      assert Critter.react(mob, mob.object.guid, 1_000) == mob
      assert Critter.react(mob, nil, 1_000) == mob
    end

    test "death cancels queued fleeing and respawn starts with clean state", %{mob: mob} do
      mob = Core.take_damage(mob, 1, 1_000, source: 1)
      {_status, mob} = BT.tick(MobBT.tree(), mob, context(1_000))
      assert mob.internal.navigation_intents != []
      dead = Core.take_damage(mob, 100, 1_000, source: 1)
      assert dead.internal.navigation_intents == []
      respawned = Mob.respawn(dead)
      assert respawned.unit.health == 20
      assert respawned.internal.blackboard == nil
      assert Bitwise.band(respawned.unit.flags, 0x800000) == 0
      assert Mob.critter?(respawned)
    end
  end

  describe "SpellEffect.receive/4" do
    test "a harmful debuff triggers escape without health loss", %{mob: mob} do
      {mob, _events} = SpellEffect.receive(mob, 1, spell(:mod_attack_power), 1_000)
      assert mob.unit.health == 20
      assert mob.internal.blackboard.critter.escape_at == 31_000
      assert Bitwise.band(mob.unit.flags, 0x800000) != 0
    end

    test "resisted and helpful spells do not trigger escape", %{mob: mob} do
      context = %CastContext{caster_guid: 1, caster_level: 1, hit_outcome: :resist}
      {resisted, _events} = SpellEffect.receive(mob, context, spell(:mod_root), 1_000)
      assert resisted.internal.blackboard.critter == nil

      helpful = %{
        spell(:mod_attack_power)
        | effects: [%Effect{index: 0, type: :heal, base_points: 2, implicit_target_a: :target_ally}]
      }

      {healed, _events} = SpellEffect.receive(mob, 1, helpful, 1_000)
      assert healed.internal.blackboard.critter == nil
    end

    test "prevent fleeing suppresses movement until removed", %{mob: mob} do
      {mob, _events} = SpellEffect.receive(mob, 1, spell(:prevent_fleeing), 1_000)
      assert mob.internal.blackboard.critter.escape_at == 31_000
      assert Bitwise.band(mob.unit.flags, 0x800000) == 0
      assert {{:running, 500, :flee}, mob} = BT.tick(MobBT.tree(), mob, context(1_000))
      assert mob.internal.navigation_intents == []
      {mob, _events} = Aura.remove_aura_types(mob, [:prevent_fleeing], 2_000)
      assert Bitwise.band(mob.unit.flags, 0x800000) != 0
      assert {{:running, 1_500, :flee}, _mob} = BT.tick(MobBT.tree(), mob, context(2_000))
    end

    test "periodic damage refreshes the owner-held escape deadline", %{mob: mob} do
      dot = %{
        spell(:periodic_damage)
        | effects: [
            %Effect{
              index: 0,
              type: :apply_aura,
              aura: :periodic_damage,
              base_points: 1,
              amplitude_ms: 1_000,
              implicit_target_a: :target_enemy
            }
          ]
      }

      {mob, _events} = SpellEffect.receive(mob, 1, dot, 1_000)
      {_status, mob} = BehaviorRunner.tick(MobBT.tree(), mob, context(2_000))
      assert mob.unit.health == 19
      assert mob.internal.blackboard.critter.escape_at == 32_000
      assert mob.internal.blackboard.combat.flee_until == 31_000
    end
  end

  describe "BehaviorRunner.tick/3" do
    test "flees away through bounded navigation and never melees", %{mob: mob} do
      mob = Core.take_damage(mob, 1, 1_000, source: 1)
      assert {{:running, 1_500, :flee}, mob} = BT.tick(MobBT.tree(), mob, context(1_000))
      assert [%{destination: {x, y, z}, opts: opts}] = mob.internal.navigation_intents
      assert x < 0
      assert_in_delta y, 0, 0.0001
      assert z == 0.0
      assert opts == [allow_steep: false, max_distance: 30.0]
      mob = NavigationResolver.resolve(mob, 1_000, fn _, _, destination, _ -> [destination] end)
      assert Movement.moving?(mob, 1_001)
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.MonsterMove))
      assert mob.unit.target == 0
      refute mob.internal.blackboard.combat.attack_started
    end

    test "failed paths use a bounded retry", %{mob: mob} do
      mob = Core.take_damage(mob, 1, 1_000, source: 1)
      {_status, mob} = BT.tick(MobBT.tree(), mob, context(1_000))
      mob = NavigationResolver.resolve(mob, 1_000, fn _, _, _, _ -> nil end)
      assert mob.internal.navigation_intents == []
      assert {{:running, 1_500, :flee}, _mob} = BT.tick(MobBT.tree(), mob, context(2_500))
    end

    test "roots block movement but do not delay escape and reset cleanup", %{mob: mob} do
      {mob, _events} = SpellEffect.receive(mob, 1, spell(:mod_root), 1_000)
      assert {{:running, 500, :flee}, rooted} = BT.tick(MobBT.tree(), mob, context(1_000))
      assert rooted.internal.navigation_intents == []
      assert {{:running, 0, :return_home}, escaped} = BT.tick(MobBT.tree(), rooted, context(31_000))
      refute escaped.internal.in_combat
      refute escaped.internal.rooted?
      assert escaped.unit.auras == []
      assert escaped.internal.threat == %{}
      assert escaped.internal.blackboard.critter == nil
      assert Bitwise.band(escaped.unit.flags, 0x800000) == 0
    end

    test "escape restores health, tap, gait, and home navigation", %{mob: mob} do
      mob = mob |> Engagement.claim(%Tap{player: 1}) |> Core.take_damage(3, 1_000, source: 1)
      mob = %{mob | movement_block: %{mob.movement_block | position: {15.0, 0.0, 0.0, 0.0}}}
      assert {{:running, 0, :return_home}, escaped} = BT.tick(MobBT.tree(), mob, context(31_000))
      assert escaped.unit.health == 20
      assert escaped.internal.loot.tapped_by == nil
      refute escaped.internal.running
      assert [%{destination: destination}] = escaped.internal.navigation_intents
      assert destination == {0.0, 0.0, 0.0}
      escaped = NavigationResolver.resolve(escaped, 31_000, fn _, _, destination, _ -> [destination] end)
      arrived = Movement.sync_position(escaped, 41_000)
      assert {:success, arrived} = BT.tick(MobBT.tree(), arrived, context(41_000))
      assert arrived.movement_block.position == {0.0, 0.0, 0.0, 0.75}
      assert arrived.internal.blackboard.navigation.move_target == nil
    end

    test "an ended flee waits for the refreshed escape timer without attacking", %{mob: mob} do
      mob = mob |> Core.take_damage(1, 1_000, source: 1) |> Core.take_damage(1, 5_000, source: 2)
      assert {{:running, 1_000, :critter_escape}, mob} = BT.tick(MobBT.tree(), mob, context(31_000))
      assert mob.internal.in_combat
      assert mob.internal.blackboard.combat.flee_until == nil
      assert Bitwise.band(mob.unit.flags, 0x800000) == 0
      assert mob.internal.navigation_intents == []
      assert {{:running, 0, :return_home}, _mob} = BT.tick(MobBT.tree(), mob, context(35_000))
    end
  end

  describe "Aura.remove_on_evade/2" do
    test "preserves timed player buffs and explicit exceptions", %{mob: mob} do
      holders = [
        holder(10, false, 1, 60_000),
        holder(11, false, 1, -1),
        holder(12, true, 1, 60_000),
        holder(13, false, mob.object.guid, 60_000),
        %{holder(14, true, 1, -1) | spell: %Spell{id: 14, custom_flags: 0x400}}
      ]

      {mob, _events} = Aura.remove_on_evade(%{mob | unit: %{mob.unit | auras: holders}}, 1_000)
      assert Enum.map(mob.unit.auras, & &1.spell.id) == [10, 14]
    end

    test "the creature exception preserves all positive auras", %{mob: mob} do
      holders = [holder(10, false, mob.object.guid, -1), holder(11, true, 1, 60_000)]

      mob = %{
        mob
        | unit: %{mob.unit | auras: holders},
          internal: %{mob.internal | creature: %{mob.internal.creature | extra_flags: 0x1000}}
      }

      {mob, _events} = Aura.remove_on_evade(mob, 1_000)
      assert Enum.map(mob.unit.auras, & &1.spell.id) == [10]
    end
  end

  defp holder(id, negative?, caster, expires_at) do
    %Holder{spell: %Spell{id: id}, caster_guid: caster, expires_at: expires_at, negative?: negative?}
  end

  defp spell(aura) do
    %Spell{
      id: 900_001,
      school: :shadow,
      duration_ms: 60_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, base_points: -1, implicit_target_a: :target_enemy}]
    }
  end

  defp context(now) do
    world = WorldRef.open(0)
    observation = %Observation{guid: 1, position: {world, 1.0, 0.0, 0.0}, metadata: %{alive?: true}}
    Context.new(now, perception: Perception.new(now, nil, %{1 => observation}, %{}))
  end

  defp mob(_context) do
    unit = %Unit{health: 20, max_health: 20, level: 1, flags: 0, target: 0, auras: [], faction_template: 31}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, walk_speed: 2.5, run_speed: 7.0, movement_flags: 0}

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 721, 1)},
      unit: unit,
      movement_block: movement,
      internal: %Internal{
        world: WorldRef.open(0),
        running: false,
        creature: %Creature{critter?: true, creature_type: 8, regenerate_stats: 0},
        loot: %Loot{},
        spawn: %Spawn{
          unit: unit,
          movement_block: movement,
          position: {0.0, 0.0, 0.0},
          home_orientation: 0.75,
          movement_type: 0
        }
      }
    }

    %{mob: BT.init(mob, MobBT.tree())}
  end
end
