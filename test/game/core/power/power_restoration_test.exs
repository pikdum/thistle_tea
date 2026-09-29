defmodule ThistleTea.Game.Core.Power.PowerRestorationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Power.PowerRestoration
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect.Resource

  setup [:recipient]

  describe "apply/3" do
    test "caps resources while logging the spell amount", %{entity: entity, grant: grant} do
      {entity, [event]} = PowerRestoration.apply(entity, grant, 1_000)
      assert entity.unit.power1 == 100
      assert entity.internal.broadcast_update?
      assert %Effects.SpellEnergize{source_guid: 2, target_guid: 1, spell_id: 123, power_type: 0, amount: 50} = event
    end

    test "restores an inactive mana pool", %{entity: entity, grant: grant} do
      entity = %{entity | unit: %{entity.unit | power_type: 3, power4: 40, max_power4: 100}}
      {entity, [_]} = PowerRestoration.apply(entity, grant, 1_000)
      assert {entity.unit.power1, entity.unit.power4} == {100, 40}
    end

    test "rejects dead recipients, absent pools, invalid types, and negative gains", ctx do
      for entity <- [
            %{ctx.entity | unit: %{ctx.entity.unit | health: 0}},
            %{ctx.entity | unit: %{ctx.entity.unit | max_power1: 0}}
          ] do
        assert PowerRestoration.apply(entity, ctx.grant, 1_000) == {entity, []}
      end

      for grant <- [%{ctx.grant | amount: -1}, %{ctx.grant | misc_value: -1}, %{ctx.grant | misc_value: 5}] do
        assert PowerRestoration.apply(ctx.entity, grant, 1_000) == {ctx.entity, []}
      end
    end
  end

  describe "apply/5" do
    test "caster-targeted energize retains its spell and source until owner delivery", ctx do
      spell = %{
        ctx.grant.spell
        | effects: [
            %Effect{index: 0, type: :energize, implicit_target_a: :caster, base_points: 50, misc_value: 0}
          ]
      }

      context = %CastContext{caster_guid: 2, caster_level: 60}
      {entity, [grant]} = Resource.apply(ctx.entity, context, spell, hd(spell.effects), 100)
      assert entity.unit.power1 == 80
      assert %Effects.GrantPower{source_guid: 2, target_guid: 2, amount: 50, spell: ^spell} = grant
    end
  end

  defp recipient(_context) do
    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, power_type: 0, power1: 80, max_power1: 100, auras: []},
      internal: %Internal{}
    }

    grant = %Effects.GrantPower{source_guid: 2, target_guid: 1, misc_value: 0, amount: 50, spell: %Spell{id: 123}}
    %{entity: entity, grant: grant}
  end
end
