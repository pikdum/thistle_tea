defmodule ThistleTea.Game.Entity.Logic.WeaponProcsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.WeaponProcs
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect

  setup [:combatants]

  describe "chance/3" do
    test "item PPM overrides DBC chance and uses base weapon speed" do
      assert_in_delta WeaponProcs.chance(%Spell{proc_chance: 100}, 8.0, 1900), 25.333333, 0.00001
      assert WeaponProcs.chance(%Spell{proc_chance: 5}, 2.0, 3000) == 10
      assert WeaponProcs.chance(%Spell{proc_chance: 101}, 0.0, 3000) == 5
      assert WeaponProcs.chance(%Spell{proc_chance: 20}, 0.0, 3000) == 20
      assert WeaponProcs.chance(%Spell{proc_chance: 0}, 0.0, 3000) == 0
      assert WeaponProcs.chance(%Spell{proc_chance: 101}, 0.0, 0) == 0
    end
  end

  describe "swing_events/4" do
    test "accepts damaging swings and blocks but rejects misses, full absorption and dead targets", %{target: target} do
      for outcome <- [:normal, :crit, :glancing, :crushing, :block] do
        assert [%Effects.TriggerWeaponProcs{hand: :offhand, extra_attack?: true}] =
                 WeaponProcs.swing_events(
                   target,
                   %{caster: 1, offhand?: true, extra_attack?: true},
                   %{outcome: outcome, damage: 10},
                   2
                 )
      end

      for outcome <- [:miss, :dodge, :parry, :evade, :immune] do
        assert WeaponProcs.swing_events(target, %{caster: 1}, %{outcome: outcome, damage: 10}, 0) == []
      end

      assert WeaponProcs.swing_events(target, %{caster: 1}, %{outcome: :normal, damage: 10}, 10) == []

      assert [%Effects.TriggerWeaponProcs{}] =
               WeaponProcs.swing_events(target, %{caster: 1}, %{outcome: :block, damage: 0}, 0)

      dead = %{target | unit: %{target.unit | health: 0}}
      assert WeaponProcs.swing_events(dead, %{caster: 1}, %{outcome: :normal, damage: 10}, 0) == []
      assert WeaponProcs.swing_events(target, %{caster: 2}, %{outcome: :normal, damage: 10}, 0) == []

      assert WeaponProcs.swing_events(
               target,
               %{caster: Guid.from_low_guid(:mob, 1, 1)},
               %{outcome: :normal, damage: 10},
               0
             ) == []
    end
  end

  describe "spell_events/3" do
    test "qualifies weapon-range and explicit spells without depending on proc origin", %{target: target} do
      context = %CastContext{caster_guid: 1, triggered?: true, triggered_by_aura?: true}
      weapon = %Spell{equipped_item_class: 2, melee_range?: true}
      assert [%Effects.TriggerWeaponProcs{hand: :mainhand}] = WeaponProcs.spell_events(target, context, weapon)
      assert WeaponProcs.spell_events(target, context, %{weapon | melee_range?: false}) == []
      assert WeaponProcs.spell_events(target, %{context | proc_damage?: true}, weapon) == []

      assert [%Effects.TriggerWeaponProcs{hand: :mainhand}] =
               WeaponProcs.spell_events(target, context, %Spell{custom_flags: 0x2000})
    end

    test "a successful multi-effect spell reports one weapon hit and a non-damaging hit still reports", %{
      target: target
    } do
      for effects <- [
            [],
            [%Effect{type: :school_damage, base_points: 5}, %Effect{type: :school_damage, base_points: 7}]
          ] do
        spell = %Spell{id: 10, school: :physical, equipped_item_class: 2, melee_range?: true, effects: effects}
        context = %CastContext{caster_guid: 1, caster_level: 60, spell: spell}
        resolution = %SpellEffect.Resolution{context: context, spell: spell, outcome: :hit, kind: :effects}
        {_target, events} = SpellEffect.apply_prepared(target, resolution, 1_000)
        assert Enum.count(events, &is_struct(&1, Effects.TriggerWeaponProcs)) == 1

        {_target, events} =
          SpellEffect.apply_prepared(target, %{resolution | kind: :launch_resist, outcome: :resist}, 1_000)

        refute Enum.any?(events, &is_struct(&1, Effects.TriggerWeaponProcs))
      end
    end
  end

  describe "innate_events/6" do
    test "only on-hit slots roll and triggers preserve the weapon, hand and implicit targeting", context do
      template = %{
        context.template
        | spellid_2: 11,
          spelltrigger_2: 0,
          spellid_3: 12,
          spelltrigger_3: 1,
          spellid_5: 13,
          spelltrigger_5: 2
      }

      item = Item.build(template, 99)
      spells = Map.new(10..13, &{&1, %Spell{id: &1, proc_chance: 100}})
      hit = %{context.hit | hand: :offhand}
      assert {events, true} = WeaponProcs.innate_events(context.caster, hit, item, spells, 1_000, fn -> 0 end)
      assert Enum.map(events, & &1.spell_id) == [10, 13]

      assert Enum.all?(
               events,
               &(&1.cast_item_guid == 99 and &1.attack_hand == :offhand and &1.target_guid == 2 and &1.resolve_targets?)
             )
    end

    test "GCD and the actual chance gate individual spells", context do
      spell = %Spell{id: 10, proc_chance: 101, gcd_category: 1, gcd_ms: 1500}
      item = Item.build(context.template, 99)
      caster = Cooldowns.trigger_gcd(context.caster, spell, 1_000)
      spells = %{10 => spell}
      assert {[], true} = WeaponProcs.innate_events(caster, context.hit, item, spells, 2499, fn -> 0 end)
      assert {[_], true} = WeaponProcs.innate_events(caster, context.hit, item, spells, 2500, fn -> 0.04 end)
      assert {[], true} = WeaponProcs.innate_events(caster, context.hit, item, spells, 2500, fn -> 0.06 end)
      assert {[], true} = WeaponProcs.innate_events(caster, context.hit, item, %{}, 2500, fn -> 0 end)
    end

    test "an extra attack proc stops recursive batches and subsequent enchant rolls", context do
      extra = %Spell{id: 10, proc_chance: 100, effects: [%Effect{type: :add_extra_attacks}]}
      item = Item.build(context.template, 99)
      spells = %{10 => extra}

      assert {[], false} =
               WeaponProcs.innate_events(
                 context.caster,
                 %{context.hit | extra_attack?: true},
                 item,
                 spells,
                 1_000,
                 fn -> 0 end
               )

      caster = ExtraAttacks.grant(context.caster, 1)
      assert {[], false} = WeaponProcs.innate_events(caster, context.hit, item, spells, 1_000, fn -> 0 end)
      assert {[_], true} = WeaponProcs.innate_events(context.caster, context.hit, item, spells, 1_000, fn -> 0 end)
    end
  end

  defp combatants(_context) do
    caster = %Mob{object: %Object{guid: 1}, unit: %Unit{level: 60, health: 100, max_health: 100}, internal: %Internal{}}
    template = %ItemTemplate{entry: 1, class: 2, delay: 3000, spellid_1: 10, spelltrigger_1: 2}

    %{
      caster: caster,
      target: %{caster | object: %Object{guid: 2}},
      template: template,
      hit: %Effects.TriggerWeaponProcs{source_guid: 1, target_guid: 2, hand: :mainhand}
    }
  end
end
