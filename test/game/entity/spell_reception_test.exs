defmodule ThistleTea.Game.Entity.SpellReceptionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Metadata
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
