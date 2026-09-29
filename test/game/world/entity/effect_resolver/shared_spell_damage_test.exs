defmodule ThistleTea.Game.World.Entity.EffectResolver.SharedSpellDamageTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  setup [:entities]

  describe "complete/3" do
    test "divides each recipient's base amount and truncates remainders", ctx do
      deliveries = cast(ctx.caster, ctx.spell)
      assert length(deliveries) == 3

      for delivery <- deliveries do
        assert delivery.cast_context.effect_target_counts == %{0 => 3}
        assert damage(ctx.targets, delivery) == 100
      end
    end

    test "counts living recipients in the same world and within the effect radius", ctx do
      [first, second, third] = ctx.targets
      Metadata.update(second.object.guid, %{alive?: false})
      SpatialHash.update(:players, third.object.guid, WorldRef.instance(0, 999), 2.0, 0.0, 0.0)
      [delivery] = cast(ctx.caster, ctx.spell)
      assert delivery.target_guid == first.object.guid
      assert delivery.cast_context.effect_target_counts == %{0 => 1}
      assert damage(ctx.targets, delivery) == 302

      SpatialHash.update(:players, first.object.guid, ctx.world, 50.0, 0.0, 0.0)
      assert cast(ctx.caster, ctx.spell) == []
    end

    test "applies target limits before counting shares", ctx do
      deliveries = cast(ctx.caster, %{ctx.spell | max_targets: 2})
      assert length(deliveries) == 2
      assert Enum.all?(deliveries, &(&1.cast_context.effect_target_counts == %{0 => 2}))
      assert Enum.all?(deliveries, &(damage(ctx.targets, &1) == 151))
    end

    test "retains counts when recipients disappear after launch", ctx do
      [delivery | _] = cast(ctx.caster, ctx.spell)
      Enum.each(ctx.targets, &SpatialHash.remove(:players, &1.object.guid))
      assert damage(ctx.targets, delivery) == 100
    end

    test "keeps independent effect recipients and does not divide other effects", ctx do
      [first | _] = ctx.targets
      extra = %Effect{index: 1, type: :school_damage, base_points: 90, implicit_target_a: :target_enemy}
      spell = %{ctx.spell | effects: ctx.spell.effects ++ [extra]}
      deliveries = cast(ctx.caster, spell, Target.unit(first.object.guid))

      for delivery <- deliveries do
        assert delivery.cast_context.effect_target_counts == %{0 => 3, 1 => 1}
        expected = if delivery.target_guid == first.object.guid, do: 190, else: 100
        assert damage(ctx.targets, delivery) == expected
      end
    end

    test "leaves ordinary area damage unchanged", ctx do
      spell = Semantics.compile(%{ctx.spell | script_name: nil, semantics: nil})
      assert Enum.all?(cast(ctx.caster, spell), &(damage(ctx.targets, &1) == 302))
    end

    test "launch resists do not redistribute their share", ctx do
      [first | rest] = ctx.targets
      spell = %{ctx.spell | attributes: MapSet.new([:cant_crit, :no_reflection])}
      Metadata.update(first.object.guid, %{aoe_avoidance: 100})
      Enum.each(rest, &Metadata.update(&1.object.guid, %{no_spell_defense?: true}))
      :rand.seed(:exsss, {1, 1, 66})
      deliveries = cast(ctx.caster, spell)
      assert length(deliveries) == 3
      missed = Enum.find(deliveries, &(&1.target_guid == first.object.guid))
      assert missed.cast_context.hit_outcome == :resist
      assert damage(ctx.targets, missed) == 0

      for hit <- Enum.reject(deliveries, &(&1 == missed)) do
        assert hit.cast_context.effect_target_counts == %{0 => 3}
        assert damage(ctx.targets, hit) == 100
      end
    end
  end

  describe "resolve/2" do
    test "triggered casts use the same per-effect shares", ctx do
      trigger = Effects.trigger_spell(ctx.caster.object.guid, 60, hd(ctx.targets).object.guid, ctx.spell.id)
      deliveries = ctx.caster |> Spells.resolve(trigger) |> deliveries()
      assert length(deliveries) == 3
      assert Enum.all?(deliveries, &(&1.cast_context.effect_target_counts == %{0 => 3}))
      assert Enum.all?(deliveries, &(damage(ctx.targets, &1) == 100))
    end

    test "foreign triggers resolve through their caster", ctx do
      target = hd(ctx.targets)
      trigger = Effects.trigger_spell(ctx.caster.object.guid, 60, target.object.guid, ctx.spell.id)
      target = %{target | internal: %{target.internal | spellbook: %{ctx.spell.id => ctx.spell}}}
      assert [%Effects.TriggerSpellRequest{}] = Spells.resolve(target, trigger)
    end
  end

  describe "receive/4" do
    test "resisted and school-immune recipients retain their share", ctx do
      [first, second | _] = ctx.targets
      deliveries = cast(ctx.caster, ctx.spell)
      missed = Enum.find(deliveries, &(&1.target_guid == first.object.guid))
      context = %{missed.cast_context | hit_outcome: :resist}
      assert {^first, [%Effects.SpellLogMiss{reason: :resist}]} = SpellEffect.receive(first, context, ctx.spell, 1_000)

      immunity = %Holder{spell: %Spell{id: 900_002}, auras: [%Aura{type: :school_immunity, misc_value: 4}]}
      second = %{second | unit: %{second.unit | auras: [immunity]}}
      immune = Enum.find(deliveries, &(&1.target_guid == second.object.guid))

      assert {^second, [%Effects.SpellLogMiss{reason: :immune}]} =
               SpellEffect.receive(second, immune.cast_context, ctx.spell, 1_000)

      third = Enum.find(deliveries, &(&1.target_guid not in [first.object.guid, second.object.guid]))
      assert damage(ctx.targets, third) == 100
    end

    test "splits the base before outgoing bonuses and target mitigation", ctx do
      target = hd(ctx.targets)
      [effect] = ctx.spell.effects
      spell = %{ctx.spell | effects: [%{effect | bonus_coefficient: 1.0}]}

      context = %CastContext{
        caster_guid: ctx.caster.object.guid,
        caster_level: 60,
        target_hostile?: true,
        effect_target_counts: %{0 => 3},
        spell_damage_bonus: %{fire: 40},
        damage_done_multiplier: 2.0
      }

      {damaged, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert target.unit.health - damaged.unit.health == 280
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 280}, &1))

      reduction = %Holder{
        spell: %Spell{id: 900_003},
        auras: [%Aura{type: :mod_damage_percent_taken, amount: -50, misc_value: 4}]
      }

      target = %{target | unit: %{target.unit | auras: [reduction]}}
      {damaged, _events} = SpellEffect.receive(target, context, spell, 1_000)
      assert target.unit.health - damaged.unit.health == 140

      spell = %{spell | attributes: MapSet.delete(spell.attributes, :cant_crit)}
      context = %{context | spell_crit_chance: 100}
      {damaged, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert target.unit.health - damaged.unit.health == 210
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 210, crit?: true}, &1))
    end
  end

  defp cast(caster, spell, targets \\ Target.none()) do
    cast = %Cast{spell: spell, targets: targets, ends_at: 1_000}
    caster = %{caster | internal: %{caster.internal | casting: cast}}
    caster = Casting.complete(caster, cast, 1_000)
    deliveries(caster.internal.events)
  end

  defp deliveries(events), do: Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))

  defp damage(targets, delivery) do
    target = Enum.find(targets, &(&1.object.guid == delivery.target_guid))
    {damaged, _events} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1_000)
    target.unit.health - damaged.unit.health
  end

  defp entities(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))

    spell =
      Semantics.compile(%Spell{
        id: 900_001,
        school: :fire,
        dmg_class: 1,
        script_name: "spell_meteor",
        attributes: MapSet.new([:always_hit, :cant_crit]),
        effects: [
          %Effect{
            index: 0,
            type: :school_damage,
            base_points: 302,
            area_target?: true,
            implicit_target_a: :aoe_enemy_at_caster,
            radius_yards: 10.0
          }
        ]
      })

    caster = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))},
      unit: %Unit{level: 60, health: 10_000, max_health: 10_000, faction_template: 17, auras: []},
      internal: %Internal{world: world, spellbook: %{spell.id => spell}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    faction = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, enemy_group: 12}

    targets =
      for x <- [1.0, 2.0, 3.0] do
        target = %Character{
          object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
          unit: %Unit{level: 60, health: 10_000, max_health: 10_000, faction_template: 1, auras: []},
          internal: %Internal{world: world},
          movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}}
        }

        SpatialHash.insert(:players, target.object.guid, world, x, 0.0, 0.0)
        Metadata.put(target.object.guid, %{alive?: true, level: 60, unit_flags: 0, faction_template: faction})
        target
      end

    Metadata.put(caster.object.guid, %{
      alive?: true,
      level: 60,
      unit_flags: 0,
      faction_template: %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}
    })

    on_exit(fn ->
      Metadata.delete(caster.object.guid)

      for target <- targets do
        Metadata.delete(target.object.guid)
        SpatialHash.remove(:players, target.object.guid)
      end
    end)

    %{caster: caster, targets: targets, spell: spell, world: world}
  end
end
