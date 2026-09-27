defmodule ThistleTea.Game.Entity.Logic.Aura.PeriodicSequenceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:whirl]

  describe "tick/2" do
    test "advances the reference sequence and wraps after eight emitted ticks", %{entity: entity} do
      expected = [24_821, 24_822, 24_823, 24_835, 24_836, 24_837, 24_838, 24_820]

      expected
      |> Kernel.++(expected)
      |> Enum.with_index(1)
      |> Enum.reduce(entity, fn {spell_id, count}, current ->
        {next, events} = Aura.tick(current, count * 5_000)
        assert [%Effects.TriggerSpell{spell_id: ^spell_id, source_guid: 1, target_guid: 1}] = triggers(events)
        assert hd(hd(next.unit.auras).auras).tick_count == count
        assert Aura.next_event_at(next) == (count + 1) * 5_000
        assert {^next, []} = Aura.tick(next, count * 5_000)
        next
      end)
    end

    test "a delayed wakeup advances one sequence step without emitting catch-up casts", %{entity: entity} do
      {entity, events} = Aura.tick(entity, 12_000)
      assert [%Effects.TriggerSpell{spell_id: 24_821}] = triggers(events)
      assert Aura.next_event_at(entity) == 15_000
      {entity, events} = Aura.tick(entity, 15_000)
      assert [%Effects.TriggerSpell{spell_id: 24_822}] = triggers(events)
      assert hd(hd(entity.unit.auras).auras).tick_count == 2
    end

    test "ordinary triggers keep their configured spell", %{entity: entity, spell: spell} do
      {entity, _events} = Aura.remove_spells(entity, [spell.id], 0)
      effect = %{hd(spell.effects) | trigger_spell_id: 123}
      spell = %{spell | id: 999_903, effects: [effect]}
      {entity, _events} = Aura.apply_spell(entity, 1, 60, spell, 0)
      {entity, events} = Aura.tick(entity, 5_000)
      assert [%Effects.TriggerSpell{spell_id: 123}] = triggers(events)
      {_entity, events} = Aura.tick(entity, 10_000)
      assert [%Effects.TriggerSpell{spell_id: 123}] = triggers(events)
    end

    test "removal expiry and death stop the sequence", %{entity: entity, spell: spell} do
      {removed, _events} = Aura.remove_spells(entity, [spell.id], 1_000)
      killed = Core.take_damage(entity, 1_000, 1_000)
      {finite, _events} = Aura.apply_spell(removed, 1, 60, %{spell | duration_ms: 5_000}, 0)
      {expired, events} = Aura.tick(finite, 5_000)
      assert [%Effects.TriggerSpell{spell_id: 24_821}] = triggers(events)

      for stopped <- [removed, killed, expired] do
        assert stopped.unit.auras == []
        assert Aura.next_event_at(stopped) == nil
        assert {^stopped, []} = Aura.tick(stopped, 10_000)
      end
    end
  end

  describe "apply_spell/5" do
    test "refresh restarts the sequence and interval", %{entity: entity, spell: spell} do
      {entity, _events} = Aura.tick(entity, 5_000)
      {entity, _events} = Aura.tick(entity, 10_000)
      {refreshed, _events} = Aura.apply_spell(entity, 1, 60, spell, 11_000)
      assert hd(hd(refreshed.unit.auras).auras).tick_count == 0
      assert Aura.next_event_at(refreshed) == 16_000
      assert {^refreshed, []} = Aura.tick(refreshed, 15_000)
      {_entity, events} = Aura.tick(refreshed, 16_000)
      assert [%Effects.TriggerSpell{spell_id: 24_821}] = triggers(events)
    end
  end

  defp triggers(events), do: Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

  defp whirl(_context) do
    spell = %Spell{
      id: 24_834,
      duration_ms: -1,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :periodic_trigger_spell,
          implicit_target_a: :caster,
          amplitude_ms: 5_000,
          trigger_spell_id: 0
        }
      ]
    }

    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
      internal: %Internal{}
    }

    {entity, _events} = Aura.apply_spell(entity, 1, 60, spell, 0)
    %{entity: entity, spell: spell}
  end
end
