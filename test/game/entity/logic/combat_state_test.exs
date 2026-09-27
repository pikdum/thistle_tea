defmodule ThistleTea.Game.Entity.Logic.CombatStateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.CombatState
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target

  setup [:actors]

  describe "enter/2" do
    test "interrupts delayed peaceful casts once and resets their global cooldown", ctx do
      for entity <- [ctx.player, ctx.mob, ctx.pet], now <- [1_001, -10_000] do
        casting = prepare(entity, ctx.spell, now)
        entered = CombatState.enter(casting, now)
        assert entered.internal.in_combat
        assert Bitwise.band(entered.unit.flags, 0x80000) != 0
        assert entered.internal.casting == nil
        refute Map.has_key?(entered.internal.cooldowns, {:gcd, 133})
        assert entered.unit.power1 == 500
        assert [%Effects.SpellCastFailed{spell_id: 100, reason: :interrupted}] = entered.internal.events
        assert {:idle, ^entered} = Casting.advance(entered, now + 30_000)
        assert CombatState.enter(entered, now + 1) == entered
      end
    end

    test "preserves combat spells, instant preparation, and spells already launched", ctx do
      ordinary = %{ctx.spell | attributes: MapSet.new()}
      instant = %{ctx.spell | cast_time_ms: 0}

      for entity <- [ctx.player, ctx.mob, ctx.pet],
          casting <- [
            prepare(entity, ordinary, 1_000),
            prepare(entity, instant, 1_000),
            put_phase(prepare(entity, ctx.spell, 1_000), :launch),
            put_phase(prepare(entity, ctx.spell, 1_000), :impact)
          ] do
        entered = CombatState.enter(casting, 1_500)
        assert entered.internal.in_combat
        assert entered.internal.casting == casting.internal.casting
        assert entered.internal.cooldowns == casting.internal.cooldowns
        assert entered.internal.events == []
      end
    end

    test "combat refresh and dead entities do not run entry interruption", ctx do
      casting = prepare(ctx.player, ctx.spell, 1_000)
      active = %{casting | internal: %{casting.internal | in_combat: true}}
      assert CombatState.enter(active, 1_500).internal.casting == casting.internal.casting
      dead = %{casting | unit: %{casting.unit | health: 0}}
      assert CombatState.enter(dead, 1_500) == dead
      assert PlayerCombat.gain_threat_ref(dead, ctx.mob.object.guid, 7, 1_500) == dead
    end

    test "interrupts hostile-action creature channels and clears channel projection", ctx do
      spell = %{
        ctx.spell
        | cast_time_ms: 0,
          duration_ms: 10_000,
          channel_interrupt_flags: 1,
          attributes: MapSet.new([:channeled])
      }

      for entity <- [ctx.mob, ctx.pet] do
        channeling = prepare_channel(entity, spell)
        entered = CombatState.enter(channeling, 1_500)
        assert entered.internal.casting == nil
        assert entered.unit.channel_object == 0
        assert entered.unit.channel_spell == 0
        assert Enum.any?(entered.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1))
        assert Enum.any?(entered.internal.events, &match?(%Effects.SpellCastFailed{reason: :interrupted}, &1))
      end

      for entity <- [
            prepare_channel(ctx.player, spell),
            prepare_channel(ctx.mob, %{spell | channel_interrupt_flags: 2})
          ] do
        assert CombatState.enter(entity, 1_500).internal.casting == entity.internal.casting
      end
    end
  end

  describe "enter/2 through gameplay transitions" do
    test "player contact, holds, and threat membership share interruption", ctx do
      casting = prepare(ctx.player, ctx.spell, 1_000)

      for entered <- [
            PlayerCombat.mark_attacked(casting, 1_500, nil, ctx.mob.object.guid),
            PlayerCombat.mark_initiated(casting, 1_500, ctx.mob.object.guid),
            PlayerCombat.hold_combat(casting, 1_500, 5_000),
            PlayerCombat.gain_threat_ref(casting, ctx.mob.object.guid, 7, 1_500)
          ] do
        assert entered.internal.in_combat
        assert entered.internal.casting == nil
        assert [%Effects.SpellCastFailed{reason: :interrupted}] = entered.internal.events
      end
    end

    test "creature engagement and pet references share interruption", ctx do
      for entity <- [ctx.mob, ctx.pet] do
        casting = prepare(entity, ctx.spell, 1_000)
        %Engagement.Result{entity: entered} = Engagement.enter(casting, 2, 1_500)
        assert entered.internal.casting == nil
        assert entered.internal.in_combat
        assert Enum.any?(entered.internal.events, &match?(%Effects.SpellCastFailed{reason: :interrupted}, &1))
      end

      casting = prepare(ctx.pet, ctx.spell, 1_000)

      for entered <- [
            Engagement.gain_threat_ref(casting, ctx.mob.object.guid, 7, 1_500),
            Engagement.contact(casting, 2, 1_500),
            Engagement.hold_combat(casting, 1_500, 5_000)
          ] do
        assert entered.internal.casting == nil
        assert entered.internal.in_combat
      end
    end
  end

  defp prepare(entity, spell, now) do
    cast = Cast.new(spell, Target.none(), now)
    %{entity | internal: %{entity.internal | casting: cast, cooldowns: %{{:gcd, 133} => now + 1_500}, events: []}}
  end

  defp put_phase(entity, phase),
    do: %{entity | internal: %{entity.internal | casting: %{entity.internal.casting | phase: phase}}}

  defp prepare_channel(entity, spell) do
    entity = entity |> prepare(spell, 1_000) |> put_phase(:channel_tick)
    %{entity | unit: %{entity.unit | channel_object: 2, channel_spell: spell.id}}
  end

  defp actors(_context) do
    unit = %Unit{health: 100, max_health: 100, power1: 500, max_power1: 500, flags: 0, auras: []}
    internal = %Internal{blackboard: Blackboard.new(), events: []}
    player = %Character{object: %Object{guid: 1}, unit: unit, internal: internal}
    mob = %Mob{object: %Object{guid: Guid.runtime(:mob, 1)}, unit: unit, internal: internal}
    pet = %{mob | object: %Object{guid: Guid.runtime(:pet, 1)}, internal: %{internal | pet: %Pet{owner_guid: 1}}}
    spell = %Spell{id: 100, cast_time_ms: 10_000, gcd_category: 133, attributes: MapSet.new([:not_in_combat])}
    %{player: player, mob: mob, pet: pet, spell: spell}
  end
end
