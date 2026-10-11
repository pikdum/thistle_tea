defmodule ThistleTea.Game.Core.Aura.GolemaggsTrustTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Test.Unique

  setup [:boss]

  describe "tick/2" do
    test "an idle boss does not refresh his ragers", %{boss: boss, spell: spell} do
      {boss, _events} = Aura.apply_spell(boss, boss.object.guid, 63, spell, 0)
      {boss, events} = Aura.tick(boss, 1_000)
      assert events == []
      assert Aura.next_event_at(boss) == 2_000
    end

    test "an engaged caster pulses every second and stops on evade", %{boss: boss, spell: spell} do
      boss = %{boss | internal: %{boss.internal | in_combat: true}}
      {boss, _events} = Aura.apply_spell(boss, boss.object.guid, 63, spell, 0)
      assert Aura.next_event_at(boss) == 1_000
      assert {^boss, []} = Aura.tick(boss, 999)
      {boss, events} = Aura.tick(boss, 1_000)
      assert [%Effects.TriggerCreatureSpellInRange{spell_id: 20_553, creature_entry: 11_672, radius: 30.0}] = events
      assert hd(events).triggering_spell_id == 20_556
      assert Aura.next_event_at(boss) == 2_000

      {boss, events} = Aura.tick(boss, 2_000)
      assert [%Effects.TriggerCreatureSpellInRange{}] = events
      boss = %{boss | internal: %{boss.internal | in_combat: false}}
      {boss, events} = Aura.tick(boss, 3_000)
      assert events == []
      assert Aura.has_spell?(boss, 20_556)
    end

    test "dead and foreign casters never refresh the buff", %{boss: boss, spell: spell} do
      boss = %{boss | internal: %{boss.internal | in_combat: true}}
      {foreign, _events} = Aura.apply_spell(boss, Unique.integer(), 63, spell, 0)
      {_foreign, events} = Aura.tick(foreign, 1_000)
      assert events == []

      {dead, _events} = Aura.apply_spell(boss, boss.object.guid, 63, spell, 0)
      dead = %{dead | unit: %{dead.unit | health: 0}}
      {_dead, events} = Aura.tick(dead, 1_000)
      assert events == []
    end

    test "scripted dummy data uses the same one-second cadence", %{boss: boss, spell: spell} do
      boss = %{boss | internal: %{boss.internal | in_combat: true}}
      spell = %{spell | effects: [%{hd(spell.effects) | aura: :dummy, amplitude_ms: 0, trigger_spell_id: 0}]}
      {boss, _events} = Aura.apply_spell(boss, boss.object.guid, 63, spell, 0)
      assert Aura.next_event_at(boss) == 1_000
      {_boss, events} = Aura.tick(boss, 1_000)
      assert [%Effects.TriggerCreatureSpellInRange{}] = events
    end
  end

  defp boss(_context) do
    %{
      boss: %Mob{
        object: %Object{guid: Unique.integer(), entry: 11_988},
        unit: %Unit{health: 100, max_health: 100, level: 63, auras: []},
        internal: %Internal{in_combat: false}
      },
      spell: %Spell{
        id: 20_556,
        duration_ms: -1,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            trigger_spell_id: 20_553,
            amplitude_ms: 1_000,
            implicit_target_a: :caster
          }
        ]
      }
    }
  end
end
