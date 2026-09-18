defmodule ThistleTea.Game.Entity.Logic.EmpathyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Empathy
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:beast]

  describe "visible_to?/2" do
    test "grants information only to empathy casters" do
      unit = %Unit{
        auras: [
          %Holder{caster_guid: 2, caster_owner_guid: 3, auras: [%AuraData{type: :empathy}]},
          %Holder{caster_guid: 4, auras: [%AuraData{type: :mod_stalked}]}
        ]
      }

      assert Empathy.visible_to?(unit, 2)
      refute Empathy.visible_to?(unit, 3)
      refute Empathy.visible_to?(unit, 4)
      refute Empathy.visible_to?(unit, nil)
      refute Empathy.visible_to?(%Unit{}, 2)
    end
  end

  describe "sync/1" do
    test "preserves other flags and clears stale information" do
      unit = %Unit{dynamic_flags: 0x0D, auras: [%Holder{auras: [%AuraData{type: :empathy}]}]}
      active = Empathy.sync(unit)
      assert active.dynamic_flags == 0x1D
      assert Empathy.sync(active) == active

      for holders <- [[], nil] do
        assert Empathy.sync(%{active | auras: holders}).dynamic_flags == 0x0D
      end
    end
  end

  describe "project/2" do
    test "hides the tooltip flag from bystanders without changing sparse updates" do
      unit = %Unit{
        dynamic_flags: 0x1D,
        auras: [%Holder{caster_guid: 2, auras: [%AuraData{type: :empathy}]}]
      }

      assert Empathy.project(unit, 2).dynamic_flags == 0x1D
      assert Empathy.project(unit, 3).dynamic_flags == 0x0D
      assert Empathy.project(%Unit{health: 50}, 2) == %Unit{health: 50}
    end
  end

  describe "apply_spell/5" do
    test "a replacement caster receives access while the former caster loses it", %{beast: beast, spell: spell} do
      {active, _events} = Aura.apply_spell(beast, 2, 60, spell, 1_000)
      {replaced, _events} = Aura.apply_spell(active, 3, 60, spell, 2_000)

      assert length(replaced.unit.auras) == 1
      refute Empathy.visible_to?(replaced.unit, 2)
      assert Empathy.visible_to?(replaced.unit, 3)
      assert replaced.unit.dynamic_flags == 0x10
    end

    test "refresh extends access until the new expiry", %{beast: beast, spell: spell} do
      {active, _events} = Aura.apply_spell(beast, 2, 60, spell, 1_000)
      assert active.unit.dynamic_flags == 0x10
      assert active.internal.broadcast_update?
      assert Empathy.visible_to?(active.unit, 2)

      {refreshed, _events} = Aura.apply_spell(active, 2, 60, spell, 11_000)
      assert length(refreshed.unit.auras) == 1
      {refreshed, _events} = Aura.expire_due(refreshed, 31_000)
      assert Empathy.visible_to?(refreshed.unit, 2)

      {expired, _events} = Aura.expire_due(refreshed, 41_000)
      assert expired.unit.dynamic_flags == 0
      refute Empathy.visible_to?(expired.unit, 2)
      assert Aura.next_event_at(expired) == nil
    end

    test "removing one source retains the other caster's information", %{beast: beast, spell: spell} do
      {active, _events} = Aura.apply_spell(beast, 2, 60, spell, 1_000)
      other_spell = %{spell | id: 2_000}
      {active, _events} = Aura.apply_spell(active, 3, 60, other_spell, 2_000)
      assert Empathy.visible_to?(active.unit, 2)
      assert Empathy.visible_to?(active.unit, 3)

      {removed, _events} = Aura.remove_source_spell(active, spell.id, 2, 3_000)
      refute Empathy.visible_to?(removed.unit, 2)
      assert Empathy.visible_to?(removed.unit, 3)
      assert removed.unit.dynamic_flags == 0x10

      {expired, _events} = Aura.expire_due(removed, 32_000)
      assert expired.unit.dynamic_flags == 0
      refute Empathy.visible_to?(expired.unit, 3)
    end

    test "death revokes access through normal aura cleanup", %{beast: beast, spell: spell} do
      {active, _events} = Aura.apply_spell(beast, 2, 60, spell, 1_000)
      dead = Core.take_damage(active, 100, 2_000)

      assert dead.unit.health == 0
      refute Empathy.visible_to?(dead.unit, 2)
      assert Empathy.project(dead.unit, 2).dynamic_flags == dead.unit.dynamic_flags
      assert Bitwise.band(dead.unit.dynamic_flags, 0x10) == 0
      assert Aura.next_event_at(dead) == nil
    end
  end

  defp beast(_context) do
    beast = %Mob{
      object: %Object{guid: 10},
      unit: %Unit{health: 100, max_health: 100, auras: [], dynamic_flags: 0},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    spell = %Spell{
      id: 1462,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :empathy, implicit_target_a: :target_enemy}]
    }

    %{beast: beast, spell: spell}
  end
end
