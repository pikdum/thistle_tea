defmodule ThistleTea.Game.Entity.SpellReceptionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Aura.Heartbeat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:target]

  describe "receive/4" do
    test "reads current modifiers from the original caster on each dispel", ctx do
      Metadata.put(ctx.caster, %{dispel_resistance: protection()})
      assert {target, [%Effects.DispelFailed{}]} = receive_dispel(ctx)
      assert target == ctx.target

      Metadata.update(ctx.caster, %{dispel_resistance: []})
      {target, events} = receive_dispel(ctx)
      assert target.unit.auras == []
      assert Enum.any?(events, &match?(%Effects.SpellDispel{}, &1))
    end

    test "does not borrow protection from the dispeller", ctx do
      Metadata.put(ctx.caster, %{dispel_resistance: []})
      Metadata.put(ctx.dispeller, %{dispel_resistance: protection()})
      {target, _events} = receive_dispel(ctx)
      assert target.unit.auras == []
    end

    test "a missing caster supplies no resistance", ctx do
      {target, _events} = receive_dispel(ctx)
      assert target.unit.auras == []
    end

    test "pet-cast auras use their owner's modifiers while the pet exists", ctx do
      Metadata.put(ctx.caster, %{})
      Metadata.put(ctx.owner, %{dispel_resistance: protection()})
      [holder] = ctx.target.unit.auras
      target = %{ctx.target | unit: %{ctx.target.unit | auras: [%{holder | caster_owner_guid: ctx.owner}]}}
      ctx = %{ctx | target: target}
      assert {^target, [%Effects.DispelFailed{}]} = receive_dispel(ctx)

      Metadata.delete(ctx.caster)
      {target, _events} = receive_dispel(ctx)
      assert target.unit.auras == []
    end

    test "self-cast protection uses current owner state instead of stale metadata", ctx do
      [holder] = ctx.target.unit.auras
      talent = %Holder{spell: %Spell{id: 20, spell_family: 7}, auras: [elem(hd(protection()), 1)]}
      holder = %{holder | caster_guid: ctx.target.object.guid, negative?: false}
      target = %{ctx.target | unit: %{ctx.target.unit | auras: [holder, talent]}}
      Metadata.put(target.object.guid, %{dispel_resistance: []})
      assert {^target, [%Effects.DispelFailed{}]} = receive_dispel(%{ctx | target: target}, true)
    end
  end

  describe "aura_contexts/2" do
    test "supplies a fresh roll for a due creature heartbeat without periodic effects", ctx do
      [holder] = ctx.target.unit.auras
      holder = %{holder | expires_at: 20_000, heartbeat: %Heartbeat{next_check_at: 5_000, hit_chance_bp: 0}}
      target = %{ctx.target | unit: %{ctx.target.unit | auras: [holder]}}
      key = {holder.spell.id, holder.caster_guid, holder.item_source}
      assert SpellReception.aura_contexts(target, 4_999) == %{}
      assert %{^key => %CastContext{heartbeat_roll: roll}} = contexts = SpellReception.aura_contexts(target, 5_000)
      assert roll in 0..10_000
      {ticked, _} = AuraLogic.tick(target, 5_000, contexts)
      assert ticked.unit.auras == [] or hd(ticked.unit.auras).heartbeat.next_check_at == 10_000
      assert SpellReception.aura_contexts(target, 20_000) == %{}
    end

    test "life drains require a living caster in the target's world", ctx do
      for type <- [:periodic_leech, :periodic_health_funnel] do
        spell = %Spell{
          id: 40,
          school: :physical,
          duration_ms: 6_000,
          effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: 10, amplitude_ms: 1_000}]
        }

        {target, _events} = AuraLogic.apply_spell(ctx.target, ctx.caster, 60, spell, 0)
        Metadata.put(ctx.caster, %{alive?: true})
        SpatialHash.update(:mobs, ctx.caster, target.internal.world, 0.0, 0.0, 0.0)
        on_exit(fn -> SpatialHash.remove(:mobs, ctx.caster) end)
        {target, events} = projected_tick(target, 1_000)
        assert target.unit.health == 90
        assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 10}, &1))

        Metadata.update(ctx.caster, %{alive?: false})
        {target, events} = projected_tick(target, 2_000)
        assert target.unit.health == 90
        assert events == []

        Metadata.update(ctx.caster, %{alive?: true})
        SpatialHash.update(:mobs, ctx.caster, WorldRef.open(1), 0.0, 0.0, 0.0)
        {target, events} = projected_tick(target, 3_000)
        assert target.unit.health == 90
        assert events == []

        SpatialHash.remove(:mobs, ctx.caster)
        Metadata.delete(ctx.caster)
        {target, events} = projected_tick(target, 4_000)
        assert target.unit.health == 90
        assert events == []

        Metadata.put(ctx.caster, %{alive?: true})
        SpatialHash.update(:mobs, ctx.caster, target.internal.world, 0.0, 0.0, 0.0)
        {target, events} = projected_tick(target, 5_000)
        assert target.unit.health == 80
        assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 10}, &1))
      end
    end
  end

  defp projected_tick(target, now) do
    AuraLogic.tick(target, now, SpellReception.aura_contexts(target, now))
  end

  defp receive_dispel(ctx, hostile? \\ false) do
    spell = %Spell{id: 30, effects: [%Effect{index: 0, type: :dispel, misc_value: 1}]}
    context = %CastContext{caster_guid: ctx.dispeller, target_hostile?: hostile?}
    SpellReception.receive(ctx.target, context, spell, 2_000)
  end

  defp protection do
    [{7, %Aura{type: :add_flat_modifier, misc_value: 28, class_mask: 2, amount: 100}}]
  end

  defp target(_context) do
    Metadata.init()
    [guid, caster, dispeller, owner] = guids = Enum.map(1..4, fn _ -> System.unique_integer([:positive]) end)
    on_exit(fn -> Enum.each(guids, &Metadata.delete/1) end)

    holder = %Holder{
      spell: %Spell{id: 10, spell_family: 7, family_flags_0: 2, dispel_type: 1},
      caster_guid: caster,
      negative?: true,
      auras: [%Aura{type: :dummy}]
    }

    target = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, auras: [holder]},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{target: target, caster: caster, dispeller: dispeller, owner: owner}
  end
end
