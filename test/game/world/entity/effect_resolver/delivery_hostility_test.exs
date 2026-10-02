defmodule ThistleTea.Game.World.Entity.EffectResolver.DeliveryHostilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  setup [:entities]

  describe "resolved_delivery/2" do
    test "decides target hostility when the delivery asks for a check", ctx do
      effect = Effects.deliver_spell(ctx.enemy, context(ctx.caster), %Spell{id: 1}, hostility_check: [])

      assert [%Effects.DeliverSpell{hostility_check: nil, cast_context: %CastContext{target_hostile?: true}}] =
               Spells.resolved_delivery(ctx.caster, effect)

      effect = Effects.deliver_spell(ctx.ally, context(ctx.caster), %Spell{id: 1}, hostility_check: [])

      assert [%Effects.DeliverSpell{cast_context: %CastContext{target_hostile?: false}}] =
               Spells.resolved_delivery(ctx.caster, effect)
    end

    test "keeps the producer's hostility without a check", ctx do
      effect = Effects.deliver_spell(ctx.enemy, context(ctx.caster), %Spell{id: 1})

      assert [%Effects.DeliverSpell{cast_context: %CastContext{target_hostile?: nil}}] =
               Spells.resolved_delivery(ctx.caster, effect)
    end
  end

  defp context(%Mob{} = caster), do: %CastContext{caster_guid: caster.object.guid, caster_level: 60}

  defp entities(_context) do
    horde = %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}
    alliance = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}

    caster = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, Unique.integer())},
      unit: %Unit{level: 60, health: 100, max_health: 100, faction_template: 17},
      internal: %Internal{}
    }

    enemy = Guid.from_low_guid(:player, Unique.integer())
    ally = Guid.from_low_guid(:mob, 2, Unique.integer())

    Metadata.put(caster.object.guid, %{alive?: true, unit_flags: 0, faction_template: horde})
    Metadata.put(enemy, %{alive?: true, unit_flags: 0, faction_template: alliance})
    Metadata.put(ally, %{alive?: true, unit_flags: 0, faction_template: horde})

    on_exit(fn -> Enum.each([caster.object.guid, enemy, ally], &Metadata.delete/1) end)

    %{caster: caster, enemy: enemy, ally: ally}
  end
end
