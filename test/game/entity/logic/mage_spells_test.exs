defmodule ThistleTea.Game.Entity.Logic.MageSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  describe "Cold Snap" do
    test "clears only active Mage Frost cooldowns" do
      cold_snap = %Spell{
        id: 12_472,
        script_name: "spell_mage_cold_snap",
        effects: [%Effect{index: 0, type: :dummy}]
      }

      frost_nova = %Spell{id: 122, spell_family: 3, school: :frost, recovery_time_ms: 25_000}
      fire_blast = %Spell{id: 2136, spell_family: 3, school: :fire, recovery_time_ms: 8_000}
      frost_shock = %Spell{id: 8056, spell_family: 11, school: :frost, recovery_time_ms: 6_000}

      caster = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, auras: []},
        internal: %Internal{
          cooldowns: %{122 => 30_000, 2136 => 10_000, 8056 => 8_000},
          spellbook: %{122 => frost_nova, 2136 => fire_blast, 8056 => frost_shock}
        }
      }

      context = %CastContext{caster_guid: 1, caster_level: 60}
      {caster, _events} = SpellEffect.receive(caster, context, cold_snap, 1_000)

      assert caster.internal.cooldowns == %{2136 => 10_000, 8056 => 8_000}
      assert [%{type: :clear_cooldown, spell_id: 122}] = caster.internal.events
    end
  end
end
