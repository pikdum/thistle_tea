defmodule ThistleTea.Game.Entity.Logic.PercentManaRecoveryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "apply_spell/5" do
    test "defaults missing amplitudes to one second", %{entity: entity} do
      for amplitude <- [nil, 0] do
        {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(amplitude_ms: amplitude), 100)
        assert Aura.next_event_at(entity) == 1_100
        assert entity.unit.power1 == 100
      end
    end

    test "preserves explicit amplitudes and refresh cadence", %{entity: entity} do
      spell = recovery(amplitude_ms: 4_000)
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 3_000)
      assert Aura.next_event_at(entity) == 4_000
      assert hd(entity.unit.auras).expires_at == 8_000
      {entity, _events} = Aura.tick(entity, 4_000)
      assert entity.unit.power1 == 200
      assert Aura.next_event_at(entity) == 8_000
    end
  end

  describe "tick/2" do
    test "restores a percentage of current maximum mana for players and creatures", %{entity: entity} do
      player = %Character{object: entity.object, unit: entity.unit, internal: entity.internal}

      for entity <- [entity, player] do
        {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(), 0)
        {entity, events} = Aura.tick(entity, 999)
        assert entity.unit.power1 == 100
        assert events == []
        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.power1 == 200
        assert entity.internal.broadcast_update?
        assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{aura_type: :obs_mod_mana, amount: 100}, &1))
        assert Enum.any?(events, &match?(%Effects.HealThreat{amount: 50.0}, &1))
        entity = %{entity | unit: %{entity.unit | max_power1: 2_000}}
        {entity, _events} = Aura.tick(entity, 2_000)
        assert entity.unit.power1 == 400
      end
    end

    test "caps restoration and generates threat only from actual gain", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 970}}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(), 0)
      {entity, events} = Aura.tick(entity, 1_000)
      assert entity.unit.power1 == 1_000
      assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: 100}, &1))
      assert Enum.any?(events, &match?(%Effects.HealThreat{amount: 15.0}, &1))
      {entity, events} = Aura.tick(entity, 2_000)
      assert entity.unit.power1 == 1_000
      refute Enum.any?(events, &match?(%Effects.HealThreat{}, &1))
      assert Aura.next_event_at(entity) == 3_000
    end

    test "restores underlying mana while another resource is active", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power_type: 3, power4: 20, max_power4: 100}}
      {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(), 0)
      {entity, _events} = Aura.tick(entity, 1_000)
      assert entity.unit.power1 == 200
      assert entity.unit.power4 == 20
    end

    test "scales stacks and ignores nonpositive percentages", %{entity: entity} do
      spell = %{recovery() | stack_amount: 3}
      {stacked, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
      {stacked, _events} = Aura.apply_spell(stacked, 2, 60, spell, 0)
      {stacked, _events} = Aura.tick(stacked, 1_000)
      assert stacked.unit.power1 == 300

      for amount <- [0, -10] do
        {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(base_points: amount), 0)
        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.power1 == 100
        refute Enum.any?(events, &match?(%Effects.HealThreat{}, &1))
      end
    end

    test "ignores units without mana and passive auras on corpses", %{entity: entity} do
      spell = %{recovery() | attributes: MapSet.new([:passive])}

      for unit <- [%{entity.unit | max_power1: 0}, %{entity.unit | health: 0}] do
        {entity, _events} = Aura.apply_spell(%{entity | unit: unit}, 2, 60, spell, 0)
        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.power1 == 100
        refute Enum.any?(events, &match?(%Effects.PeriodicAuraLog{}, &1))
        assert Aura.next_event_at(entity) == 2_000
      end
    end

    test "does not replay every missed tick after a delayed update", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(), 0)
      {entity, events} = Aura.tick(entity, 3_500)
      assert entity.unit.power1 == 200
      assert Enum.count(events, &match?(%Effects.PeriodicAuraLog{}, &1)) == 1
      assert Aura.next_event_at(entity) == 4_000
    end

    test "expires after its final tick", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(), 0)
      {entity, _events} = Aura.tick(entity, 5_000)
      assert entity.unit.power1 == 200
      assert entity.unit.auras == []
      assert Aura.next_event_at(entity) == nil
      {entity, _events} = Aura.tick(entity, 6_000)
      assert entity.unit.power1 == 200
    end
  end

  describe "remove_with_interrupt_flags/3" do
    test "standing and movement stop seated recovery", %{entity: entity} do
      spell = %{recovery() | aura_interrupt_flags: 0x40000}

      for reason <- [:stand, :move] do
        {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
        assert entity.unit.stand_state == 1
        {entity, _events} = Aura.remove_with_interrupt_flags(entity, Aura.interrupt_mask(reason), 500)
        {entity, _events} = Aura.tick(entity, 1_000)
        assert entity.unit.power1 == 100
        assert Aura.next_event_at(entity) == nil
      end
    end
  end

  describe "remove_spells/3" do
    test "cancellation and death clear pending recovery", %{entity: entity} do
      {entity, _events} = Aura.apply_spell(entity, 2, 60, recovery(), 0)
      {cancelled, _events} = Aura.remove_spells(entity, [1], 500)
      dead = Core.take_damage(entity, 1_000, 500)

      for entity <- [cancelled, dead] do
        {entity, _events} = Aura.tick(entity, 1_000)
        assert entity.unit.power1 == 100
        assert entity.unit.auras == []
        assert Aura.next_event_at(entity) == nil
      end
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 1_000, power1: 100, max_power1: 1_000, level: 60, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp recovery(opts \\ []) do
    effect = %Effect{index: 0, type: :apply_aura, aura: :obs_mod_mana, amplitude_ms: 1_000, base_points: 10}
    %Spell{id: 1, duration_ms: 5_000, effects: [struct!(effect, opts)]}
  end
end
