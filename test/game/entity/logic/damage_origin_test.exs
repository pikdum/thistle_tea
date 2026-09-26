defmodule ThistleTea.Game.Entity.Logic.DamageOriginTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.DamageOrigin, as: Totals
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura.Periodic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.DamageOrigin
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  setup [:creature]

  describe "loot_allowed?/1" do
    test "requires strictly more than 35 percent player damage", %{mob: mob} do
      for {player, npc, allowed, multiplier} <- [
            {0, 0, false, 0.0},
            {0, 100, false, 0.0},
            {34, 66, false, 0.0},
            {35, 65, false, 0.0},
            {36, 64, true, 0.36},
            {100, 0, true, 1.0}
          ] do
        mob = %{mob | internal: %{mob.internal | damage_origin: %Totals{player: player, npc: npc}}}
        assert DamageOrigin.loot_allowed?(mob) == allowed
        assert DamageOrigin.xp_multiplier(mob) == multiplier
      end
    end

    test "raid corpses bypass contribution restrictions", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | creature: %Creature{static_flags: 0x1000}}}
      assert DamageOrigin.loot_allowed?(mob)
      assert DamageOrigin.xp_multiplier(mob) == 1.0
    end
  end

  describe "take_damage/4" do
    test "retains overkill and healing history through death", %{mob: mob, npc: npc} do
      mob = Core.take_damage(mob, 40, 1, source: 7)
      mob = Core.heal(mob, 40)
      dead = Core.take_damage(mob, 100, 2, source: npc)
      assert dead.internal.damage_origin == %Totals{player: 40, npc: 100}
      assert dead.internal.loot.tapped_by == nil
      assert Core.take_damage(dead, 500, 3, source: 7).internal.damage_origin == dead.internal.damage_origin
    end

    test "attributes controlled attackers and self damage", %{mob: mob, npc: npc} do
      pet = Guid.from_low_guid(:pet, 1, 1)
      mob = Core.take_damage(mob, 10, 1, source: pet, source_owner: 7)
      mob = Core.take_damage(mob, 10, 2, source: 7, source_owner: npc)
      mob = Core.take_damage(mob, 10, 3, source: mob.object.guid)
      mob = Core.take_damage(mob, 10, 4, source: 8, source_owner: 0)
      assert mob.internal.damage_origin == %Totals{player: 30, npc: 10}
    end

    test "excludes absorption and immunity before counting damage", %{mob: mob} do
      shield = %Holder{spell: %Spell{id: 17}, auras: [%Aura{type: :school_absorb, amount: 30, misc_value: 1}]}
      mob = %{mob | unit: %{mob.unit | auras: [shield]}}
      mob = Core.take_damage(mob, 20, 1, source: 7)
      assert mob.internal.damage_origin == %Totals{}
      mob = Core.take_damage(mob, 20, 2, source: 7)
      assert mob.internal.damage_origin == %Totals{player: 10}
      immunity = %Holder{spell: %Spell{id: 1022}, auras: [%Aura{type: :school_immunity, misc_value: 1}]}
      mob = %{mob | unit: %{mob.unit | auras: [immunity]}}
      assert Core.take_damage(mob, 50, 3, source: 7).internal.damage_origin == %Totals{player: 10}
    end

    test "counts damage before a scripted health threshold", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | invincibility_health_threshold: 10}}
      mob = Core.take_damage(mob, 200, 1, source: 7)
      assert mob.unit.health == 10
      assert mob.internal.damage_origin == %Totals{player: 200}
    end

    test "captures the lethal contribution before shard eligibility", %{mob: mob, npc: npc} do
      shard = %Holder{
        spell: %Spell{id: 1120, spell_family: 5},
        caster_guid: 7,
        auras: [%Aura{type: :channel_death_item, item_type: 6265, amount: 1}]
      }

      for {player, npc_damage, eligible?} <- [{35, 65, false}, {36, 64, true}] do
        hurt = Core.take_damage(mob, npc_damage, 1, source: npc)
        hurt = %{hurt | unit: %{hurt.unit | auras: [shard]}}
        dead = Core.take_damage(hurt, player, 2, source: 7)

        assert [%Effects.DeathItemReward{victim: victim}] =
                 Enum.filter(dead.internal.events, &is_struct(&1, Effects.DeathItemReward))

        assert victim.shard_target? == eligible?
        assert DamageOrigin.loot_allowed?(dead) == eligible?
        assert is_nil(dead.internal.loot.tapped_by) == not eligible?
      end
    end
  end

  describe "tick/2" do
    test "periodic damage retains the caster's controlling owner", %{mob: mob, npc: npc} do
      holder = %Holder{
        spell: %Spell{id: 1, school: :physical},
        caster_guid: npc,
        caster_owner_guid: 7,
        caster_level: 10,
        auras: [%Aura{type: :periodic_damage, amount: 10, amplitude_ms: 1_000, next_tick_at: 1_000}]
      }

      mob = %{mob | unit: %{mob.unit | auras: [holder]}}
      {mob, _events} = Periodic.tick(mob, 1_000)
      assert mob.internal.damage_origin == %Totals{player: 10}
    end
  end

  describe "engagement lifecycle" do
    test "preserves contributions across victim changes and clears them on reset", %{mob: mob, npc: npc} do
      mob = Core.take_damage(mob, 20, 1, source: 7)
      mob = Core.take_damage(mob, 30, 2, source: npc)
      %{entity: stopped} = Engagement.stop_attack(mob)
      assert stopped.internal.damage_origin == %Totals{player: 20, npc: 30}
      %{entity: changed} = Engagement.enter(stopped, 8, 3)
      assert changed.internal.damage_origin == stopped.internal.damage_origin
      assert Engagement.leave(changed, :evade).entity.internal.damage_origin == %Totals{}
      assert Mob.respawn(changed).internal.damage_origin == %Totals{}
    end

    test "scripted self kills preserve player-side damage", %{mob: mob} do
      dead = Core.kill(mob, 1)
      assert dead.internal.damage_origin == %Totals{player: 100}
      assert dead.internal.loot.tapped_by == %Tap{player: 7}
      assert Core.kill(dead, 2) == dead
    end
  end

  describe "kill_xp/3" do
    test "rounds assisted rewards to the nearest even integer" do
      assert Experience.kill_xp(10, 10, damage_multiplier: 0.5) == 48
      assert Experience.kill_xp(12, 12, damage_multiplier: 0.5) == 52
      assert Experience.kill_xp(10, 10, damage_multiplier: 0.36) == 34
      assert Experience.kill_xp(10, 10, damage_multiplier: 0.0) == 0
    end
  end

  defp creature(_context) do
    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
      unit: %Unit{health: 100, max_health: 100, level: 10},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{creature: %Creature{}, loot: %Loot{tapped_by: %Tap{player: 7}}}
    }

    %{mob: mob, npc: Guid.from_low_guid(:mob, 2, 2)}
  end
end
