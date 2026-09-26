defmodule ThistleTea.Game.Spell.TargetTriggerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.ComboPoints
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetTrigger
  alias ThistleTea.Game.WorldRef

  setup [:combatants]

  describe "snapshot/2" do
    test "matches both family words and rejects missing masks and direct trigger loops", %{caster: caster} do
      for spell <- [
            %Spell{id: 1, spell_family: 8, family_flags_0: 1},
            %Spell{id: 1, spell_family: 8, family_flags_1: 1}
          ] do
        holder = holder(0x100000001, 100, 0)
        caster = %{caster | unit: %{caster.unit | auras: [holder]}}
        assert [%TargetTrigger{spell_id: 14_181}] = TargetTrigger.snapshot(caster, spell)
        assert TargetTrigger.snapshot(caster, %{spell | spell_family: 3}) == []
        assert TargetTrigger.snapshot(caster, %{spell | id: 14_181}) == []
      end

      for mask <- [0, nil] do
        caster = %{caster | unit: %{caster.unit | auras: [holder(mask, 100, 0)]}}
        assert TargetTrigger.snapshot(caster, strike()) == []
      end
    end
  end

  describe "events/3" do
    test "Relentless Strikes uses the cast's combo points after they are consumed", %{caster: caster} do
      for points <- 1..5 do
        caster = %{caster | player: %{caster.player | combo_points: points}}
        context = CastContext.from_caster(caster, strike(), 2)
        spent = ComboPoints.consume(caster)
        assert spent.player.combo_points == 0
        assert context.combo_points == points

        assert [
                 %Effects.TriggerSpell{
                   spell_id: 14_181,
                   source_guid: 1,
                   target_guid: 2,
                   triggering_spell_id: 14_179,
                   resolve_targets?: true
                 }
               ] =
                 TargetTrigger.events(context, 2, fn -> points / 5 end)

        if points < 5, do: assert(TargetTrigger.events(context, 2, fn -> points * 0.2 + 0.001 end) == [])
      end
    end

    test "caster-only aura restrictions prevent duplicate rolls on other recipients", %{caster: caster} do
      [holder] = caster.unit.auras
      holder = %{holder | spell: %{holder.spell | attributes: MapSet.new([:class_trigger_only_on_caster])}}
      caster = %{caster | unit: %{caster.unit | auras: [holder]}}
      context = CastContext.from_caster(caster, strike(), 2)
      assert [%Effects.TriggerSpell{}] = TargetTrigger.events(context, 1)
      assert TargetTrigger.events(context, 2) == []
      assert TargetTrigger.events(context, 3) == []
    end
  end

  describe "receive/4" do
    test "one successful multi-effect impact queues one trigger after the spell's effects", %{
      caster: caster,
      victim: victim
    } do
      spell = %{strike() | effects: [damage(0), damage(1)]}
      context = CastContext.from_caster(caster, spell, 2)
      resolution = SpellEffect.prepare(victim, context, spell)
      assert victim.unit.health == 100
      {hit, events} = SpellEffect.apply_prepared(victim, resolution, 1_000)
      assert hit.unit.health == 80
      assert Enum.count(events, &is_struct(&1, Effects.SpellDamage)) == 2
      assert [%Effects.TriggerSpell{spell_id: 14_181}] = triggers(events)
      assert is_struct(List.last(events), Effects.TriggerSpell)
    end

    test "resists, immunities and already-dead recipients produce no target triggers", %{caster: caster, victim: victim} do
      spell = strike()
      context = CastContext.from_caster(caster, spell, 2)
      {_, events} = SpellEffect.receive(victim, %{context | hit_outcome: :resist}, spell, 1_000)
      assert triggers(events) == []

      immunity = %Holder{spell: %Spell{id: 642}, auras: [%AuraData{type: :school_immunity, misc_value: 127}]}
      immune = %{victim | unit: %{victim.unit | auras: [immunity]}}
      {_, events} = SpellEffect.receive(immune, context, spell, 1_000)
      assert triggers(events) == []
      {_, events} = SpellEffect.receive(%{victim | unit: %{victim.unit | health: 0}}, context, spell, 1_000)
      assert triggers(events) == []
    end

    test "a killing blow retains the caster-targeted finisher refund", %{caster: caster, victim: victim} do
      spell = strike()
      context = CastContext.from_caster(caster, spell, 2)
      victim = %{victim | unit: %{victim.unit | health: 1}}
      {killed, events} = SpellEffect.receive(victim, context, spell, 1_000)
      assert killed.unit.health == 0
      assert [%Effects.TriggerSpell{spell_id: 14_181, resolve_targets?: true}] = triggers(events)
    end

    test "a reflected spell triggers only after its reflected impact succeeds", %{caster: caster, victim: victim} do
      reflection = %Holder{spell: %Spell{id: 123}, auras: [%AuraData{type: :reflect_spells, amount: 100}]}
      victim = %{victim | unit: %{victim.unit | auras: [reflection]}}
      spell = %{strike() | dmg_class: 1}
      context = CastContext.from_caster(caster, spell, 2)
      {_, events} = SpellEffect.receive(victim, context, spell, 1_000)
      assert triggers(events) == []
      delivery = Enum.find(events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.target_guid == 1
      {hit, events} = SpellEffect.receive(caster, delivery.cast_context, spell, 1_000)
      assert hit.unit.health == 90
      assert [%Effects.TriggerSpell{target_guid: 1}] = triggers(events)
    end

    test "triggered hits participate but repeated persistent-area applications do not", %{
      caster: caster,
      victim: victim
    } do
      spell = strike()
      context = %{CastContext.from_caster(caster, spell, 2) | triggered?: true, triggered_by_aura?: true}
      {_, events} = SpellEffect.receive(victim, context, spell, 1_000)
      assert [%Effects.TriggerSpell{}] = triggers(events)
      context = %{context | persistent_area: %{guid: 99}}
      {_, events} = SpellEffect.receive(victim, context, spell, 2_000)
      assert triggers(events) == []
    end
  end

  describe "start/5" do
    test "a direct channel triggers once at its initial impact, never on its later ticks", %{caster: caster} do
      spell = %{
        strike()
        | duration_ms: 3_000,
          attributes: MapSet.new([:channeled]),
          effects: [%Effect{index: 0, type: :heal, base_points: 1, amplitude_ms: 1_000, implicit_target_a: :caster}]
      }

      caster = Casting.start(caster, spell, Target.self(1), 1_000)
      assert length(triggers(caster.internal.events)) == 1
      caster = %{caster | internal: %{caster.internal | events: []}}
      assert {:waiting, caster, _} = Casting.advance(caster, 2_000)
      assert triggers(caster.internal.events) == []
      assert {:finished, caster} = Casting.advance(caster, 4_000)
      assert triggers(caster.internal.events) == []
    end
  end

  defp combatants(_context) do
    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: [holder(1, 0, 20)]},
      player: %Player{combo_points: 5},
      internal: %Internal{combo_target_guid: 2, world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    victim = %Mob{
      object: %Object{guid: 2},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      internal: %Internal{}
    }

    %{caster: caster, victim: victim}
  end

  defp holder(mask, amount, points) do
    %Holder{
      spell: %Spell{id: 14_179, spell_family: 8, effects: [%Effect{index: 0, points_per_combo: points}]},
      auras: [
        %AuraData{index: 0, type: :add_target_trigger, amount: amount, class_mask: mask, trigger_spell_id: 14_181}
      ]
    }
  end

  defp strike, do: %Spell{id: 2098, spell_family: 8, family_flags_0: 1, school: :shadow, effects: [damage(0)]}
  defp damage(index), do: %Effect{index: index, type: :school_damage, base_points: 10}
  defp triggers(events), do: Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))
end
