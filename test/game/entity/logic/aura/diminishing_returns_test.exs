defmodule ThistleTea.Game.Entity.Logic.Aura.DiminishingReturnsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:target]

  defp target(_context) do
    target = %Character{
      object: %Object{guid: 2},
      unit: %Unit{level: 50, health: 1_000, max_health: 1_000, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{target: target}
  end

  defp stun(id \\ 56) do
    %Spell{
      id: id,
      mechanic: 12,
      duration_ms: 8_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun, base_points: 0}]
    }
  end

  defp context(caster \\ 1) do
    %CastContext{caster_guid: caster, caster_type: :player, caster_level: 50, target_hostile?: true}
  end

  describe "apply_spell/4" do
    test "shares history across casters and sends reduced client durations", %{target: target} do
      {target, events} = Aura.apply_spell(target, context(), stun(), 0)
      assert Enum.any?(events, &match?(%Effects.AuraDuration{duration_ms: 8_000}, &1))
      {target, events} = Aura.apply_spell(target, context(3), stun(), 1_000)
      assert Enum.any?(events, &match?(%Effects.AuraDuration{duration_ms: 4_000}, &1))
      {target, events} = Aura.apply_spell(target, context(), stun(), 2_000)
      assert Enum.any?(events, &match?(%Effects.AuraDuration{duration_ms: 2_000}, &1))
      assert [%Holder{expires_at: 4_000}] = target.unit.auras

      {unchanged, events} = Aura.apply_spell(target, context(3), stun(), 3_000)
      assert unchanged == target
      assert [%Effects.SpellLogMiss{source_guid: 3, target_guid: 2, spell_id: 56, reason: :immune}] = events
    end

    test "counts multiple aura effects once", %{target: target} do
      spell = %{stun() | effects: stun().effects ++ [%Effect{index: 1, type: :apply_aura, aura: :mod_root}]}
      {target, _} = SpellEffect.receive(target, context(), spell, 0)
      assert target.internal.diminishing_returns.controlled_stun.applications == 1
      assert [%Holder{auras: [_, _], expires_at: 8_000}] = target.unit.auras
    end

    test "recovery waits for all overlapping holders to leave", %{target: target} do
      {target, _} = Aura.apply_spell(target, context(), stun(), 0)
      {target, _} = Aura.apply_spell(target, context(3), stun(57), 1_000)
      {target, _} = Aura.expire_due(target, 5_000)
      assert target.internal.diminishing_returns.controlled_stun.reset_at == nil
      {target, _} = Aura.expire_due(target, 8_000)
      assert target.internal.diminishing_returns.controlled_stun.reset_at == 23_000
      {before_reset, _} = Aura.apply_spell(target, context(), stun(), 22_999)
      assert [%Holder{expires_at: 24_999}] = before_reset.unit.auras
      {after_reset, _} = Aura.apply_spell(target, context(), stun(), 23_000)
      assert [%Holder{expires_at: 31_000}] = after_reset.unit.auras
    end

    test "dispels and damage breaks start recovery", %{target: target} do
      spell = %{stun() | dispel_type: 1, aura_interrupt_flags: 2}
      {target, _} = Aura.apply_spell(target, context(), spell, 0)
      {dispelled, _} = Aura.dispel(target, 1, 1_000, :negative)
      assert dispelled.internal.diminishing_returns.controlled_stun.reset_at == 16_000
      broken = Aura.break_on_damage(target, 2_000)
      assert broken.internal.diminishing_returns.controlled_stun.reset_at == 17_000
    end

    test "immunity attempts do not extend the recovery window", %{target: target} do
      target =
        Enum.reduce(0..2, target, fn now, target ->
          {target, _} = Aura.apply_spell(target, context(), stun(), now)
          target
        end)

      {target, _} = Aura.expire_due(target, 2_002)
      {target, [%Effects.SpellLogMiss{reason: :immune}]} = Aura.apply_spell(target, context(), stun(), 17_001)
      {target, _} = Aura.apply_spell(target, context(), stun(), 17_002)
      assert [%Holder{expires_at: 25_002}] = target.unit.auras
    end

    test "mechanic immunity and stronger ranks do not consume a step", %{target: target} do
      immunity = %Holder{spell: %Spell{id: 100}, auras: [%AuraData{type: :mechanic_immunity, misc_value: 12}]}
      immune_target = %{target | unit: %{target.unit | auras: [immunity]}}
      {immune_target, _} = Aura.apply_spell(immune_target, context(), stun(), 0)
      assert immune_target.internal.diminishing_returns == %{}

      stronger = %Holder{spell: %{stun(57) | first_in_chain: 56, rank: 2}}
      stronger_target = %{target | unit: %{target.unit | auras: [stronger]}}
      {stronger_target, _} = Aura.apply_spell(stronger_target, context(), %{stun() | first_in_chain: 56, rank: 1}, 0)
      assert stronger_target.internal.diminishing_returns == %{}
    end

    test "separates proc stuns and Kidney Shot from controlled stuns", %{target: target} do
      {target, _} = Aura.apply_spell(target, context(), stun(), 0)
      {target, _} = Aura.apply_spell(target, %{context() | triggered_by_aura?: true}, stun(57), 1_000)
      kidney = %{stun(408) | spell_family: 8, family_flags_0: 0x00200000}
      {target, _} = Aura.apply_spell(target, context(), kidney, 2_000)
      assert Enum.map(target.unit.auras, &(&1.expires_at - &1.applied_at)) == [8_000, 8_000, 8_000]

      assert Map.keys(target.internal.diminishing_returns) |> Enum.sort() ==
               [:controlled_stun, :kidney_shot, :triggered_stun]
    end

    test "death clears all diminishing history", %{target: target} do
      {target, _} = Aura.apply_spell(target, context(), stun(), 0)
      target = Core.take_damage(target, 1_000, 1_000, source: 1)
      assert target.unit.health == 0
      assert target.internal.diminishing_returns == %{}
    end
  end

  describe "receive/4" do
    test "reports immune without bonus threat and preserves non-aura damage", %{target: target} do
      target =
        Enum.reduce(0..2, target, fn now, target ->
          {target, _} = SpellEffect.receive(target, context(), stun(), now)
          target
        end)

      {target, events} = SpellEffect.receive(target, %{context() | spell_threat: %{threat: 100}}, stun(), 3)
      assert Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :immune}, &1))
      assert target.internal.threat in [nil, %{}]
      refute SpellEffect.successful_hit?(events)

      damage = %Effect{index: 1, type: :school_damage, base_points: 10, die_sides: 0}
      mixed = %{stun() | school: :physical, effects: [damage | stun().effects]}
      {target, events} = SpellEffect.receive(target, context(), mixed, 4)
      assert target.unit.health == 990
      assert Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :immune}, &1))
      assert Enum.any?(events, &is_struct(&1, Effects.SpellDamage))
    end
  end
end
