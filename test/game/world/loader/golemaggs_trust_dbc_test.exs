defmodule ThistleTea.Game.World.Loader.GolemaggsTrustDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.WeaponDamage
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Test.Unique

  @moduletag :dbc_db

  setup [:creature]

  describe "load/1" do
    test "the permanent pulse emits the combat-only scripted request", %{creature: creature} do
      spell = SpellLoader.load(20_556)
      assert spell.duration_ms == -1
      assert hd(spell.effects).aura == :periodic_trigger_spell
      {boss, _events} = Aura.apply_spell(creature, creature.object.guid, 63, spell, 0)
      assert Aura.next_event_at(boss) == 1_000
      {boss, events} = Aura.tick(boss, 1_000)
      assert events == []
      boss = %{boss | internal: %{boss.internal | in_combat: true}}
      {_boss, events} = Aura.tick(boss, 2_000)
      assert [%Effects.TriggerCreatureSpellInRange{spell_id: 20_553}] = events
    end

    test "the real buff grants damage and haste for two seconds", %{creature: creature} do
      spell = SpellLoader.load(20_553)
      assert spell.duration_ms == 2_000
      {buffed, _events} = Aura.apply_spell(creature, Unique.integer(), 63, spell, 0)
      assert buffed.unit.base_attack_time == 1_333
      assert WeaponDamage.flat_bonus(buffed, :physical, nil) == 500
      {expired, _events} = Aura.tick(buffed, 2_000)
      refute Aura.has_spell?(expired, 20_553)
      assert expired.unit.base_attack_time == 2_000
      assert WeaponDamage.flat_bonus(expired, :physical, nil) == 0
    end
  end

  defp creature(_context) do
    %{
      creature: %Mob{
        object: %Object{guid: Unique.integer(), entry: 11_988},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 63,
          base_melee_attack_time: 2_000,
          base_attack_time: 2_000,
          auras: []
        },
        internal: %Internal{in_combat: false}
      }
    }
  end
end
