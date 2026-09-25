defmodule ThistleTea.Game.Entity.Logic.Aura.PersistentAreaTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.DynamicObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.PersistentArea
  alias ThistleTea.Game.Spell.PersistentArea.Check
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:ground_spell]

  describe "tick/3" do
    test "separately delivered ground effects coexist and expire with their own sources", ctx do
      second = ground_effect(ctx, 1, 5.0, 2_000)
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      {target, _} = Aura.apply_spell(target, second, second.spell, 10)
      {target, _} = Aura.apply_spell(target, ctx.context, ctx.spell, 250)
      {target, _} = Aura.apply_spell(target, second, second.spell, 260)

      assert [%Holder{expires_at: 4_000} = holder] = ground_holders(target)
      assert Enum.map(holder.auras, & &1.index) == [0, 1]
      assert Enum.map(holder.spell.effects, & &1.index) == [0, 1]
      assert holder.cast_context.persistent_area == nil

      contexts = %{{ctx.spell.id, ctx.context.caster_guid, nil} => ground_checks(holder, 0)}
      {target, _} = Aura.tick(target, 2_000, contexts)
      assert target.unit.health == 800
      assert [%Holder{auras: [%{index: 0}]} = holder] = ground_holders(target)
      assert Enum.map(holder.spell.effects, & &1.index) == [0]
      assert Enum.map(holder.cast_context.spell.effects, & &1.index) == [0]

      {target, _} = Aura.remove_area_aura(target, second.persistent_area.guid, 2_100)
      assert length(ground_holders(target)) == 1
      {target, _} = Aura.remove_area_aura(target, ctx.area.guid, 2_100)
      assert ground_holders(target) == []
    end

    test "each ground effect rolls independently", ctx do
      second = ground_effect(ctx, 1, 5.0, 2_000)
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      {target, _} = Aura.apply_spell(target, second, second.spell, 10)

      context = %{
        ctx.context
        | area_checks: %{
            ctx.area.guid => %Check{hit_roll: 9_999},
            second.persistent_area.guid => %Check{hit_roll: 0}
          }
      }

      {target, events} = Aura.tick(target, 1_000, %{{ctx.spell.id, ctx.context.caster_guid, nil} => context})
      assert target.unit.health == 900
      assert Enum.count(events, &match?(%Effects.SpellLogMiss{reason: :resist}, &1)) == 1
      assert Enum.count(events, &match?(%Effects.SpellDamage{periodic?: true}, &1)) == 1
      assert Enum.all?(hd(ground_holders(target)).auras, &(&1.next_tick_at == 2_000))
    end

    test "overlapping sources retain an existing effect until it leaves", ctx do
      overlap = ground_effect(ctx, 0, 5.0, 5_000)
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      {target, _} = Aura.apply_spell(target, overlap, overlap.spell, 250)
      assert [%Holder{expires_at: 4_000, auras: [%{persistent_area: area}]}] = ground_holders(target)
      assert area.guid == ctx.area.guid

      {target, _} = Aura.remove_area_aura(target, ctx.area.guid, 500)
      {target, _} = Aura.apply_spell(target, overlap, overlap.spell, 750)
      {target, _} = Aura.remove_area_aura(target, ctx.area.guid, 800)
      assert [%Holder{expires_at: 5_000, auras: [%{persistent_area: area}]}] = ground_holders(target)
      assert area.guid == overlap.persistent_area.guid
    end

    test "rolls each ground damage tick without removing a resisted holder", ctx do
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      {target, events} = tick(target, ctx.context, 1_000, 8_000)
      assert target.unit.health == 1_000
      assert [%Effects.SpellLogMiss{reason: :resist}] = events
      assert hd(hd(ground_holders(target)).auras).next_tick_at == 2_000

      {target, events} = tick(target, ctx.context, 2_000, 7_099)
      assert target.unit.health == 900
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 100, periodic?: true}, &1))
      assert length(ground_holders(target)) == 1
    end

    test "ordinary dots do not reroll their hit chance", ctx do
      context = %{ctx.context | persistent_area: nil}
      {target, _} = Aura.apply_spell(ctx.target, context, ctx.spell, 0)
      {target, events} = tick(target, context, 1_000, 9_999)
      assert target.unit.health == 900
      refute Enum.any?(events, &match?(%Effects.SpellLogMiss{}, &1))
    end

    test "refreshes preserve the deadline and fixed expiry including the final tick", ctx do
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 5)
      {target, _} = Aura.apply_spell(target, ctx.context, ctx.spell, 255)
      assert [%Holder{expires_at: 4_000, auras: [%{next_tick_at: 1_000}]}] = ground_holders(target)

      target =
        Enum.reduce(1..4, target, fn n, target ->
          {target, _} = tick(target, ctx.context, n * 1_000 + 5, 0)
          target
        end)

      assert target.unit.health == 600
      assert ground_holders(target) == []
      assert Aura.next_event_at(target) == nil
      assert {^target, []} = Aura.tick(target, 8_000)
    end

    test "source cancellation cannot remove a replacement area", ctx do
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      replacement = %{ctx.context | persistent_area: %{ctx.area | guid: ctx.area.guid + 1}}
      {target, _} = Aura.remove_area_aura(target, ctx.area.guid, 100)
      {target, _} = Aura.apply_spell(target, replacement, ctx.spell, 250)
      {target, _} = Aura.remove_area_aura(target, ctx.area.guid, 500)
      assert length(ground_holders(target)) == 1
      {target, _} = Aura.remove_area_aura(target, replacement.persistent_area.guid, 500)
      assert ground_holders(target) == []
      assert {^target, []} = Aura.tick(target, 1_000)
    end
  end

  describe "aura_contexts/2" do
    test "leaving one footprint retains the other effect and its damage", ctx do
      second = ground_effect(ctx, 1, 5.0, 4_000)
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      {target, _} = Aura.apply_spell(target, second, second.spell, 10)
      target = %{target | movement_block: %{target.movement_block | position: {7.0, 0.0, 0.0, 0.0}}}
      {target, _} = Aura.tick(target, 250, SpellReception.aura_contexts(target, 250))
      assert [%Holder{auras: [%{index: 0}]}] = ground_holders(target)
      {target, _} = tick(target, ctx.context, 1_000, 0)
      assert target.unit.health == 900
    end

    test "nonperiodic ground effects are removed independently when a source disappears", ctx do
      second = ground_effect(ctx, 1, 5.0, 4_000)
      first = ground_immunity(ctx.context, 5)
      second = ground_immunity(second, 6)
      {target, _} = Aura.apply_spell(ctx.target, first, first.spell, 0)
      {target, _} = Aura.apply_spell(target, second, second.spell, 10)
      assert Enum.map(hd(ground_holders(target)).auras, & &1.misc_value) == [5, 6]

      World.remove_position(ctx.dynamic)
      {target, _} = Aura.tick(target, 250, SpellReception.aura_contexts(target, 250))
      assert [%Holder{auras: [%{index: 1, misc_value: 6}]}] = ground_holders(target)
      assert Aura.next_event_at(target) == 500
      {target, _} = Aura.tick(target, 4_000, SpellReception.aura_contexts(target, 4_000))
      assert ground_holders(target) == []
      assert Aura.next_event_at(target) == nil
    end

    test "leaving the footprint, changing worlds, or losing the source removes the holder before damage", ctx do
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 0)
      moved = %{target | movement_block: %{target.movement_block | position: {20.0, 0.0, 0.0, 0.0}}}
      transferred = %{target | internal: %{target.internal | world: WorldRef.open(1)}}

      for recipient <- [moved, transferred] do
        {cleared, events} = Aura.tick(recipient, 1_000, SpellReception.aura_contexts(recipient, 1_000))
        assert ground_holders(cleared) == []
        assert cleared.unit.health == 1_000
        refute Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
      end

      World.remove_position(ctx.dynamic)
      {cleared, _} = Aura.tick(target, 250, SpellReception.aura_contexts(target, 250))
      assert ground_holders(cleared) == []
      assert Aura.next_event_at(cleared) == nil
    end

    test "normal expiry permits the last due tick after source despawn", ctx do
      {target, _} = Aura.apply_spell(ctx.target, ctx.context, ctx.spell, 3_500)
      World.remove_position(ctx.dynamic)
      contexts = SpellReception.aura_contexts(target, 4_005)
      key = {ctx.spell.id, ctx.context.caster_guid, nil}
      context = Map.fetch!(contexts, key)
      assert context.area_checks[ctx.area.guid].available?
      context = %{context | area_checks: %{ctx.area.guid => %Check{hit_roll: 0}}}
      {target, _} = Aura.tick(target, 4_005, %{key => context})
      assert target.unit.health == 900
      assert ground_holders(target) == []
    end

    test "late delivery cannot reapply an expired or cancelled area", ctx do
      assert SpellReception.prepare(ctx.target, ctx.context, ctx.spell, 4_000) == nil
      World.remove_position(ctx.dynamic)
      assert SpellReception.prepare(ctx.target, ctx.context, ctx.spell, 500) == nil
    end
  end

  describe "DynamicObject.handle_info/2" do
    test "delivers a caster snapshot and removes recipients on cancellation", ctx do
      caster = %{ctx.target | unit: %{ctx.target.unit | faction_template: 17}}

      bonus = %Holder{
        spell: %Spell{id: 991_558},
        auras: [%ThistleTea.Game.Aura{type: :mod_spell_hit_chance, amount: 12}]
      }

      caster = %{caster | unit: %{caster.unit | auras: [bonus]}}
      target_guid = ctx.context.caster_guid
      EntityRegistry.register(target_guid)
      SpatialHash.update(:players, target_guid, ctx.target.internal.world, 0.0, 0.0, 0.0)

      Metadata.put(caster.object.guid, %{
        alive?: true,
        faction_template: %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
      })

      Metadata.put(target_guid, %{
        alive?: true,
        stealthed?: true,
        invisibility: %{0 => 100},
        unit_flags: 0,
        faction_template: %FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}
      })

      on_exit(fn ->
        SpatialHash.remove(:players, target_guid)
        Metadata.delete(caster.object.guid)
      end)

      effect = %{hd(ctx.spell.effects) | type: :persistent_area_aura}
      spell = %{ctx.spell | effects: [effect]}
      World.remove_position(ctx.dynamic)

      {:ok, pid} =
        World.start_entity(%{
          entity: ctx.dynamic,
          duration_ms: 60_000,
          tick: DynamicObjectServer.tick_config(caster, spell, effect)
        })

      on_exit(fn -> World.stop_entity(ctx.dynamic.object.guid) end)
      assert_receive {:"$gen_cast", {:receive_spell, context, delivered}}, 1_000
      assert context.spell_hit_bonus == 12
      assert context.persistent_area.guid == ctx.dynamic.object.guid
      assert context.caster_guid == caster.object.guid
      assert hd(delivered.effects).type == :apply_aura
      World.stop_entity(pid)
      area_guid = ctx.dynamic.object.guid
      assert_receive {:"$gen_cast", {:remove_area_aura, ^area_guid}}, 1_000
      assert World.position(area_guid) == nil
    end
  end

  defp ground_holders(target), do: Enum.filter(target.unit.auras, &(&1.spell.id == 991_555))

  defp tick(target, context, now, roll) do
    checks = if context.persistent_area, do: %{context.persistent_area.guid => %Check{hit_roll: roll}}, else: %{}
    contexts = %{{context.spell.id, context.caster_guid, nil} => %{context | area_checks: checks}}
    Aura.tick(target, now, contexts)
  end

  defp ground_checks(holder, roll) do
    checks = Map.new(holder.auras, &{&1.persistent_area.guid, %Check{hit_roll: roll}})
    %{holder.cast_context | area_checks: checks}
  end

  defp ground_effect(ctx, index, radius, expires_at) do
    effect = %{hd(ctx.spell.effects) | index: index}
    spell = %{ctx.spell | effects: [effect]}
    dynamic = DynamicObject.build(ctx.context.caster_guid, ctx.target.internal.world, spell, {0.0, 0.0, 0.0}, radius)
    World.update_position(dynamic)
    on_exit(fn -> World.remove_position(dynamic) end)
    area = %{ctx.area | guid: dynamic.object.guid, radius: radius, expires_at: expires_at}
    %{ctx.context | spell: spell, persistent_area: area}
  end

  defp ground_immunity(context, dispel_type) do
    effect = %{hd(context.spell.effects) | aura: :dispel_immunity, misc_value: dispel_type, amplitude_ms: nil}
    spell = %{context.spell | effects: [effect], attributes: MapSet.new([:immunity_purges_effect])}
    %{context | spell: spell}
  end

  defp ground_spell(_context) do
    guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
    caster = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    world = WorldRef.instance(0, System.unique_integer([:positive]))

    spell = %Spell{
      id: 991_555,
      duration_ms: 4_000,
      school: :fire,
      dmg_class: 1,
      hidden_aura?: true,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :periodic_damage,
          amplitude_ms: 1_000,
          base_points: 100,
          area_target?: true
        }
      ]
    }

    dynamic = DynamicObject.build(caster, world, spell, {0.0, 0.0, 0.0}, 10.0)
    World.update_position(dynamic)
    on_exit(fn -> World.remove_position(dynamic) end)
    Metadata.put(caster, %{alive?: true})
    on_exit(fn -> Metadata.delete(caster) end)

    area = %PersistentArea{
      guid: dynamic.object.guid,
      position: {world, 0.0, 0.0, 0.0},
      radius: 10.0,
      started_at: 0,
      expires_at: 4_000
    }

    avoidance = %Holder{
      spell: %Spell{id: 991_556},
      caster_guid: guid,
      auras: [%ThistleTea.Game.Aura{type: :mod_aoe_avoidance, amount: 25}]
    }

    target = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: [avoidance]},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world}
    }

    context = %CastContext{
      caster_guid: caster,
      caster_level: 60,
      spell: spell,
      persistent_area: area,
      target_hostile?: true
    }

    %{target: target, spell: spell, context: context, area: area, dynamic: dynamic}
  end
end
