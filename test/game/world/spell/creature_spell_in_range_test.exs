defmodule ThistleTea.Game.World.Spell.CreatureSpellInRangeTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.WeaponDamage
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  setup [:caster]

  describe "resolve/2" do
    test "uses a strict horizontal surface radius", ctx do
      inside = spawn_rager(ctx.caster, {33.499, 0.0, 1_000.0})
      spawn_rager(ctx.caster, {33.5, 0.0, 0.0})
      spawn_rager(ctx.caster, {33.501, 0.0, 0.0})

      effects = EffectResolver.resolve(ctx.caster, ctx.request)
      assert delivery_guids(effects) == [inside.object.guid]
    end

    test "ignores wrong entries, dead or absent owners and other copies", ctx do
      inside = spawn_rager(ctx.caster, {1.0, 0.0, 0.0})
      spawn_rager(ctx.caster, {1.0, 0.0, 0.0}, entry: 12_099)
      spawn_rager(ctx.caster, {1.0, 0.0, 0.0}, health: 0)
      missing = spawn_rager(ctx.caster, {1.0, 0.0, 0.0})
      stop_supervised!(missing.object.guid)
      other = %{ctx.caster | internal: %{ctx.caster.internal | world: WorldRef.instance(409, Unique.integer())}}
      spawn_rager(other, {1.0, 0.0, 0.0})

      effects = EffectResolver.resolve(ctx.caster, ctx.request)
      assert delivery_guids(effects) == [inside.object.guid]
    end

    test "casts once per rager with the boss as source and buffs expire normally", ctx do
      first = spawn_rager(ctx.caster, {1.0, 0.0, 0.0})
      second = spawn_rager(ctx.caster, {2.0, 0.0, 0.0})
      effects = EffectResolver.resolve(ctx.caster, ctx.request)
      deliveries = Enum.filter(effects, &is_struct(&1, Effects.DeliverSpell))
      casts = Enum.filter(effects, &is_struct(&1, Effects.SpellGo))
      assert length(casts) == 2
      assert Enum.sort(Enum.flat_map(casts, & &1.hit_guids)) == Enum.sort([first.object.guid, second.object.guid])
      assert Enum.all?(casts, &(length(&1.hit_guids) == 1 and &1.source_guid == ctx.caster.object.guid))

      for rager <- [first, second] do
        delivery = Enum.find(deliveries, &(&1.target_guid == rager.object.guid))
        assert delivery.cast_context.caster_guid == ctx.caster.object.guid
        assert delivery.cast_context.triggered_by_aura?
        {buffed, _events} = SpellEffect.receive(rager, delivery.cast_context, delivery.spell, 1_000)
        assert [%{caster_guid: caster}] = buffed.unit.auras
        assert caster == ctx.caster.object.guid
        assert buffed.unit.base_attack_time == 1_333
        assert WeaponDamage.flat_bonus(buffed, :physical, nil) == 500
        {expired, _events} = Aura.tick(buffed, 3_000)
        refute Aura.has_spell?(expired, 20_553)
        assert expired.unit.base_attack_time == 2_000
        assert WeaponDamage.flat_bonus(expired, :physical, nil) == 0
      end
    end
  end

  defp caster(_context) do
    effects =
      for {index, aura, amount, misc} <- [{0, :mod_damage_done, 500, 1}, {1, :mod_melee_haste, 50, 0}] do
        %Effect{
          index: index,
          type: :apply_aura,
          aura: aura,
          base_points: amount,
          misc_value: misc,
          implicit_target_a: :caster_source,
          implicit_target_b: :script_units_at_source,
          radius_yards: 30.0
        }
      end

    spell = Semantics.compile(%Spell{id: 20_553, duration_ms: 2_000, effects: effects})

    caster = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 11_988, Unique.integer()), entry: 11_988},
      unit: %Unit{health: 100, max_health: 100, level: 63, bounding_radius: 3.0, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.instance(409, Unique.integer()), spellbook: %{20_553 => spell}}
    }

    request = %Effects.TriggerCreatureSpellInRange{
      spell_id: 20_553,
      creature_entry: 11_672,
      radius: 30.0,
      triggering_spell_id: 20_556
    }

    %{caster: caster, request: request}
  end

  defp spawn_rager(caster, {x, y, z}, opts \\ []) do
    entry = Keyword.get(opts, :entry, 11_672)
    guid = Guid.from_low_guid(:mob, entry, Unique.integer())

    mob = %Mob{
      object: %Object{guid: guid, entry: entry},
      unit: %Unit{
        health: Keyword.get(opts, :health, 100),
        max_health: 100,
        level: 63,
        bounding_radius: 0.5,
        base_melee_attack_time: 2_000,
        base_attack_time: 2_000,
        auras: []
      },
      movement_block: %MovementBlock{position: {x, y, z, 0.0}},
      internal: %Internal{world: caster.internal.world}
    }

    start_supervised!(%{
      id: guid,
      start:
        {Agent, :start_link,
         [
           fn ->
             {:ok, _} = Entity.register(guid)
             World.update_position(mob)
             Metadata.put(guid, %{entry: entry, alive?: mob.unit.health > 0, bounding_radius: 0.5})
             mob
           end
         ]}
    })

    on_exit(fn ->
      World.remove_position(mob)
      Metadata.delete(guid)
    end)

    mob
  end

  defp delivery_guids(effects), do: for(%Effects.DeliverSpell{target_guid: guid} <- effects, do: guid)
end
