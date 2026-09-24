defmodule ThistleTea.Game.Entity.Logic.Aura.PeriodicModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "apply_spell/4" do
    test "activation modifiers change cadence without changing tick magnitude or duration", %{caster: caster} do
      for type <- [
            :periodic_damage,
            :periodic_damage_percent,
            :periodic_heal,
            :periodic_energize,
            :periodic_leech,
            :periodic_health_funnel,
            :periodic_mana_leech,
            :periodic_power_burn,
            :periodic_trigger_spell,
            :obs_mod_health,
            :obs_mod_mana
          ] do
        spell = spell(type)
        {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 1_000)

        assert [%Holder{expires_at: 11_000, auras: [%Aura{amount: 10, amplitude_ms: 2_000, next_tick_at: 3_000}]}] =
                 target.unit.auras
      end
    end

    test "family and mask mismatches preserve the original interval", %{caster: caster} do
      for spell <- [%{spell() | spell_family: 3}, %{spell() | family_flags_0: 2}] do
        {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 1_000)
        assert [%Holder{auras: [%Aura{amplitude_ms: 4_000, next_tick_at: 5_000}]}] = target.unit.auras
      end
    end

    test "refresh preserves the pending tick while adopting the new cadence", %{caster: caster} do
      spell = spell()
      {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 1_000)
      untalented = %{caster | unit: %{caster.unit | auras: []}}
      {target, _events} = AuraLogic.apply_spell(target, CastContext.from_caster(untalented, spell, 2), spell, 2_000)
      assert [%Holder{auras: [%Aura{amplitude_ms: 4_000, next_tick_at: 3_000}]}] = target.unit.auras
      {target, events} = AuraLogic.tick(target, 3_000)
      assert trigger_count(events) == 1
      assert AuraLogic.next_event_at(target) == 7_000
    end

    test "immediate pulses keep their initial tick and use the modified cadence afterward", %{caster: caster} do
      spell = %{spell() | id: 8145}
      {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 1_000)
      assert AuraLogic.next_event_at(target) == 1_000
      {target, events} = AuraLogic.tick(target, 1_000)
      assert trigger_count(events) == 1
      assert AuraLogic.next_event_at(target) == 3_000
    end
  end

  describe "tick/2" do
    test "ticks once per deadline and removes the schedule on expiry", %{caster: caster} do
      spell = spell()
      {target, _events} = AuraLogic.apply_spell(target(), CastContext.from_caster(caster, spell, 2), spell, 1_000)
      assert AuraLogic.next_event_at(target) == 3_000
      {target, events} = AuraLogic.tick(target, 2_999)
      assert trigger_count(events) == 0
      {target, events} = AuraLogic.tick(target, 3_000)
      assert trigger_count(events) == 1
      {target, events} = AuraLogic.tick(target, 3_000)
      assert trigger_count(events) == 0
      {target, events} = AuraLogic.tick(target, 6_500)
      assert trigger_count(events) == 1
      assert AuraLogic.next_event_at(target) == 7_000
      {target, events} = AuraLogic.tick(target, 11_000)
      assert trigger_count(events) == 1
      assert target.unit.auras == []
      assert AuraLogic.next_event_at(target) == nil
    end
  end

  describe "complete/2" do
    test "a charged timing modifier is spent once after its schedule is captured", %{caster: caster} do
      spell = spell()
      caster = put_in(caster.unit.auras, [%{hd(caster.unit.auras) | charges: 1}])
      assert Modifiers.consumable_holder_ids(caster, spell) == [50]
      assert Modifiers.consumable_holder_ids(caster, %{spell | effects: [%Effect{type: :school_damage}]}) == []

      completed = caster |> Casting.start(spell, Target.self(1), 1_000) |> Casting.complete(1_000)
      refute Enum.any?(completed.unit.auras, &(&1.spell.id == 50))
      assert [%Holder{auras: [%Aura{amplitude_ms: 2_000}]}] = completed.unit.auras
    end
  end

  describe "start/5" do
    test "channel triggers use the same modified schedule after the charge is spent", %{caster: caster} do
      spell = %{spell() | attributes: MapSet.new([:channeled])}
      caster = put_in(caster.unit.auras, [%{hd(caster.unit.auras) | charges: 1}])
      channel = Casting.start(caster, spell, Target.self(1), 1_000)
      assert channel.internal.casting.channel_tick_ms == 2_000
      assert channel.internal.casting.ends_at == 11_000
      refute Enum.any?(channel.unit.auras, &(&1.spell.id == 50))

      channel = %{channel | internal: %{channel.internal | events: []}}
      assert {:waiting, channel, _delay} = Casting.advance(channel, 2_999)
      assert trigger_count(channel.internal.events) == 0
      assert {:waiting, channel, _delay} = Casting.advance(channel, 3_000)
      assert trigger_count(channel.internal.events) == 1
      assert channel.internal.casting.next_channel_tick_at == 5_000
      cancelled = Casting.cancel(channel, 3_001)
      assert cancelled.internal.casting == nil
    end
  end

  defp caster(_context) do
    modifier = %Holder{
      spell: %Spell{id: 50, spell_family: 8},
      auras: [%Aura{type: :add_flat_modifier, misc_value: 19, amount: -2_000, class_mask: 1}]
    }

    target = target()
    %{caster: %{target | object: %Object{guid: 1}, unit: %{target.unit | auras: [modifier]}}}
  end

  defp target do
    %Mob{
      object: %Object{guid: 2},
      unit: %Unit{level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0},
      internal: %Internal{world: WorldRef.open(451)}
    }
  end

  defp spell(type \\ :periodic_trigger_spell) do
    %Spell{
      id: 100,
      spell_family: 8,
      family_flags_0: 1,
      duration_ms: 10_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: 10,
          amplitude_ms: 4_000,
          implicit_target_a: :caster,
          trigger_spell_id: 101
        }
      ]
    }
  end

  defp trigger_count(events), do: Enum.count(events, &is_struct(&1, Effects.TriggerSpell))
end
