defmodule ThistleTea.Game.World.Entity.EffectResolver.SpellLaunchTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Ranged
  alias ThistleTea.Game.Core.Combat.CombatTimer
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Combat
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Entity.EffectResolver.SpellLaunch
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context, as: SinkContext
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  setup [:actors]

  describe "spell launch" do
    test "preparation is peaceful and launch precedes impact without notifying the victim", ctx do
      preparing = Casting.start(ctx.caster, ctx.spell, Target.unit(ctx.target), -10_000)
      assert {:waiting, preparing, 1} = Casting.advance(preparing, -9_001)
      refute preparing.internal.in_combat
      refute Enum.any?(preparing.internal.events, &is_struct(&1, Effects.SpellLaunched))
      launched = preparing |> Casting.complete(-9_000) |> EventSink.emit_pending(SinkContext.new(self()))
      assert launched.internal.in_combat
      assert launched.unit.flags == 0x80000
      assert CombatTimer.remaining(launched, -9_000) == 1_500
      assert launched.internal.threat_refs == nil
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
      assert_receive {:deliver_spell, %Effects.DeliverSpell{delay_ms: 1_000}}, 1_500
      refute sync(launched, -7_500).internal.in_combat
      assert Metadata.get(ctx.target).in_combat == false
    end

    test "an interrupted preparation never produces a launch hold", ctx do
      interrupted = ctx.caster |> Casting.start(ctx.spell, Target.unit(ctx.target), 0) |> Casting.cancel(500)
      refute interrupted.internal.in_combat
      refute Enum.any?(interrupted.internal.events, &is_struct(&1, Effects.SpellLaunched))
    end

    test "only harmful effects belonging to the explicit recipient create a window", ctx do
      request = launch(ctx)
      refute EventSink.emit(ctx.caster, %{request | target_guid: nil}).internal.in_combat
      refute EventSink.emit(ctx.caster, %{request | effect_indices: []}).internal.in_combat
      mixed = %{ctx.spell | effects: ctx.spell.effects ++ [%Effect{index: 1, type: :heal}]}
      refute EventSink.emit(ctx.caster, %{request | spell: mixed, effect_indices: [1]}).internal.in_combat
      assert EventSink.emit(ctx.caster, %{request | spell: mixed, effect_indices: [0]}).internal.in_combat
    end

    test "a miss starts launch combat and PvE contact does not extend flight", ctx do
      context = %CastContext{
        caster_guid: ctx.caster.object.guid,
        selected_target_guid: ctx.target,
        hit_outcome: :resist
      }

      delivery = Effects.deliver_spell(ctx.target, context, ctx.spell)
      effects = [launch(ctx), delivery]
      resolved = EffectResolver.resolve(ctx.caster, effects)

      assert [
               %Effects.HoldCombat{duration_ms: 1_500},
               %Effects.DeliverSpell{delay_ms: 1_000, cast_context: %{hit_outcome: :resist}}
             ] = resolved

      launched = EventSink.emit(ctx.caster, launch(ctx))

      contact = %Effects.SpellContact{
        target_guid: ctx.caster.object.guid,
        other_guid: ctx.target,
        decision: %Combat{combat?: true},
        now: 1_000
      }

      contacted = Combat.apply_caster(launched, contact)
      assert sync(contacted, 1_499).internal.in_combat
      refute sync(contacted, 1_500).internal.in_combat
    end

    test "pet launch changes only the pet's combat state", ctx do
      pet = %Mob{
        object: %Object{guid: Guid.runtime(:pet, 8)},
        unit: ctx.caster.unit,
        movement_block: ctx.caster.movement_block,
        internal: %Internal{world: ctx.world, pet: %Pet{owner_guid: ctx.caster.object.guid}}
      }

      request = %{launch(ctx) | source_guid: pet.object.guid}
      assert [%Effects.HoldCombat{target_guid: target}] = EffectResolver.resolve(pet, request)
      assert target == pet.object.guid
      launched = EventSink.emit(pet, request)
      assert launched.internal.in_combat
      assert Bitwise.band(launched.unit.flags, 0x80800) == 0x80800
      assert launched.unit.target == nil
      assert launched.internal.threat == nil
      assert launched.internal.events == []
      refute Engagement.maintain(launched, Context.new(1_500)).internal.in_combat
    end

    test "longer holds survive later short launches and disengagement clears them", ctx do
      held = PlayerCombat.hold_combat(ctx.caster, -10_000, 6_000)
      held = EventSink.emit(held, %{launch(ctx) | now: -9_000})
      assert CombatTimer.remaining(held, -9_000) == 5_000
      assert sync(held, -4_001).internal.in_combat
      refute sync(held, -4_000).internal.in_combat
      {left, _effects} = PlayerCombat.disengage(held)
      refute sync(left, -8_000).internal.in_combat
      dead = %{ctx.caster | unit: %{ctx.caster.unit | health: 0}}
      refute EventSink.emit(dead, launch(ctx)).internal.in_combat
    end

    test "repeat shots and triggered casts enter through the same launch effects", ctx do
      shot = %{spell: ctx.spell, targets: Target.unit(ctx.target), target_guid: ctx.target}
      fired = Ranged.fire(ctx.caster, shot, 0)
      assert Enum.any?(fired.internal.events, &is_struct(&1, Effects.SpellLaunched))
      assert EventSink.emit_pending(fired).internal.in_combat
      caster = %{ctx.caster | internal: %{ctx.caster.internal | spellbook: %{ctx.spell.id => ctx.spell}}}
      trigger = Effects.trigger_spell(caster.object.guid, 50, ctx.target, ctx.spell.id, resolve_targets?: true)
      assert Enum.any?(Spells.resolve(caster, trigger), &is_struct(&1, Effects.HoldCombat))
    end

    test "foreign launch and delivery use the actual caster's position", ctx do
      source = Unique.integer()
      SpatialHash.update(:players, source, ctx.world, -20.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, source) end)
      request = %{launch(ctx) | source_guid: source}
      context = %CastContext{caster_guid: source, selected_target_guid: ctx.target}
      delivery = Effects.deliver_spell(ctx.target, context, ctx.spell)

      assert [%Effects.HoldCombat{duration_ms: 2_500}, %Effects.DeliverSpell{delay_ms: 2_000}] =
               EffectResolver.resolve(ctx.caster, [request, delivery])
    end

    test "point-blank missiles use the minimum flight distance and self casts remain immediate", ctx do
      SpatialHash.update(:mobs, ctx.target, ctx.world, 0.0, 0.0, 0.0)
      assert SpellLaunch.delay(ctx.caster, ctx.caster.object.guid, ctx.target, ctx.spell) == 250
      assert [%Effects.HoldCombat{duration_ms: 750}] = EffectResolver.resolve(ctx.caster, launch(ctx))
      assert SpellLaunch.delay(ctx.caster, ctx.caster.object.guid, ctx.caster.object.guid, ctx.spell) == 0
      SpatialHash.update(:mobs, ctx.target, WorldRef.open(998), 0.0, 0.0, 0.0)
      assert SpellLaunch.delay(ctx.caster, ctx.caster.object.guid, ctx.target, ctx.spell) == 0
    end
  end

  defp actors(_context) do
    world = WorldRef.open(999)
    source = Unique.integer()
    target = Guid.runtime(:mob, Unique.integer())
    SpatialHash.update(:mobs, target, world, 20.0, 0.0, 0.0)
    Metadata.put(target, %{alive?: true, in_combat: false, level: 50, faction_template: 14, incarnation_id: 1})

    on_exit(fn ->
      SpatialHash.remove(:mobs, target)
      Metadata.delete(target)
    end)

    caster = %Character{
      object: %Object{guid: source},
      player: %Player{},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 50,
        faction_template: 1,
        flags: 0,
        auras: [],
        ranged_attack_time: 2_000
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world}
    }

    spell = %Spell{
      id: 991_700,
      speed: 20.0,
      cast_time_ms: 1_000,
      range_yards: 40.0,
      effects: [%Effect{index: 0, type: :school_damage, base_points: 10, implicit_target_a: :target_enemy}]
    }

    %{caster: caster, target: target, world: world, spell: spell}
  end

  defp launch(ctx),
    do: %Effects.SpellLaunched{source_guid: ctx.caster.object.guid, target_guid: ctx.target, spell: ctx.spell, now: 0}

  defp sync(entity, now), do: entity |> PlayerCombat.sync(Blackboard.new(), Context.new(now)) |> elem(0)
end
