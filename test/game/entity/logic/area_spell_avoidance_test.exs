defmodule ThistleTea.Game.Entity.Logic.AreaSpellAvoidanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "area_of_effect?/1" do
    test "retains any effect's area classification through recipient filtering" do
      direct = damage_spell(false)
      area = Semantics.compile(%{direct | effects: direct.effects ++ damage_spell(true).effects})
      assert Spell.area_of_effect?(%{area | effects: direct.effects})
      refute Spell.area_of_effect?(direct)
      refute Spell.area_of_effect?(%{direct | effects: [%{hd(direct.effects) | chain_targets: 3, radius_yards: 10.0}]})
    end
  end

  describe "context_hit_chance_bp/4" do
    test "reduces area hit chance while preserving direct spells", ctx do
      target = %{level: 60, aoe_avoidance: 25}
      assert SpellResist.context_hit_chance_bp(ctx.context, damage_spell(true), target, false) == 7_100
      assert SpellResist.context_hit_chance_bp(ctx.context, damage_spell(false), target, false) == 9_600
      assert SpellResist.context_hit?(ctx.context, damage_spell(true), target, false, roll: 7_099)
      refute SpellResist.context_hit?(ctx.context, damage_spell(true), target, false, roll: 7_100)
    end

    test "combines defenses before binary resistance and final bounds", ctx do
      spell = %{
        damage_spell(true)
        | mechanic: 12,
          effects: damage_spell(true).effects ++ [%Effect{type: :apply_aura, aura: :mod_stun}]
      }

      target = %{
        level: 60,
        aoe_avoidance: 25,
        attacker_spell_hit_chance: [{4, 4}, {16, -90}],
        mechanic_resistance: [{12, 5}],
        school_resistances: %{2 => 100}
      }

      context = %{ctx.context | spell_hit_bonus: 10}
      assert SpellResist.context_hit_chance_bp(context, spell, target, true) == 6_000
      assert SpellResist.context_hit_chance_bp(context, spell, %{target | aoe_avoidance: 200}, true) == 100
      assert SpellResist.context_hit_chance_bp(context, spell, %{target | aoe_avoidance: -200}, true) == 9_900
      assert SpellResist.context_hit?(context, spell, Map.put(target, :no_spell_defense?, true), true, roll: 9_999)
      always = %{spell | attributes: MapSet.new([:always_hit])}
      assert SpellResist.context_hit_chance_bp(context, always, target, true) == 10_000
    end
  end

  describe "defense_snapshot/1" do
    test "tracks stacking, replacement, cancellation, expiry, and death", ctx do
      {target, _} = Aura.apply_spell(ctx.target, 2, 60, avoidance(901, 25), 0)
      {target, _} = Aura.apply_spell(target, 2, 60, avoidance(902, 10), 0)
      assert SpellResist.defense_snapshot(target).aoe_avoidance == 35
      {replaced, _} = Aura.apply_spell(target, 2, 60, avoidance(901, 40), 100)
      assert SpellResist.defense_snapshot(replaced).aoe_avoidance == 50
      {removed, _} = Aura.remove_spells(replaced, [901], 200)
      assert SpellResist.defense_snapshot(removed).aoe_avoidance == 10
      {expired, _} = Aura.tick(removed, 1_000)
      assert SpellResist.defense_snapshot(expired).aoe_avoidance == 0
      assert Aura.next_event_at(expired) == nil
      dead = Core.take_damage(target, target.unit.health, 500)
      assert SpellResist.defense_snapshot(dead).aoe_avoidance == 0
    end
  end

  describe "receive/4" do
    test "landed area spells retain full damage and saved misses deal none", ctx do
      {target, _} = Aura.apply_spell(ctx.target, 2, 60, avoidance(901, 25), 0)
      spell = damage_spell(true)
      {hit, events} = SpellEffect.receive(target, %{ctx.context | hit_outcome: :hit}, spell, 100)
      assert hit.unit.health == target.unit.health - 100
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 100, resisted: 0}, &1))

      assert {^target, [%Effects.SpellLogMiss{reason: :resist}]} =
               SpellEffect.receive(target, %{ctx.context | hit_outcome: :resist}, spell, 100)
    end
  end

  describe "complete/3" do
    test "normal casts read current avoidance and observe its removal", ctx do
      target = ctx.target.object.guid
      spell = damage_spell(true)
      cast = %Cast{spell: spell, targets: Target.unit(target), ends_at: 1_000}
      caster = %{ctx.caster | internal: %{ctx.caster.internal | casting: cast}}
      Metadata.update(target, %{aoe_avoidance: 100})
      :rand.seed(:exsss, {1, 1, 66})
      missed = Casting.complete(caster, cast, 1_000)
      assert Enum.any?(missed.internal.events, &match?(%Effects.SpellGo{misses: [%{reason: 2}]}, &1))

      assert Enum.any?(
               missed.internal.events,
               &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :resist}}, &1)
             )

      Metadata.update(target, %{aoe_avoidance: 0})
      :rand.seed(:exsss, {1, 1, 66})
      hit = Casting.complete(caster, cast, 1_000)
      assert Enum.any?(hit.internal.events, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :hit}}, &1))
    end
  end

  defp entities(_context) do
    caster = entity(Guid.from_low_guid(:mob, 1, System.unique_integer([:positive])))
    target = entity(Guid.from_low_guid(:player, System.unique_integer([:positive])))

    for {guid, faction} <- [
          {caster.object.guid, %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}},
          {target.object.guid, %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, enemy_group: 12}}
        ] do
      Metadata.put(guid, %{alive?: true, faction_template: faction, unit_flags: 0, level: 60})
      on_exit(fn -> Metadata.delete(guid) end)
    end

    context = %CastContext{caster_guid: caster.object.guid, caster_level: 60, target_hostile?: true}
    %{caster: caster, target: target, context: context}
  end

  defp entity(guid) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end

  defp damage_spell(area?) do
    %Spell{
      id: 900,
      school: :fire,
      dmg_class: 1,
      attributes: MapSet.new([:no_reflection]),
      effects: [
        %Effect{index: 0, type: :school_damage, base_points: 100, implicit_target_a: :target_enemy, area_target?: area?}
      ]
    }
  end

  defp avoidance(id, amount) do
    %Spell{
      id: id,
      duration_ms: 1_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_aoe_avoidance, base_points: amount}]
    }
  end
end
