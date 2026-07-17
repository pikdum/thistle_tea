defmodule ThistleTea.Game.Entity.Logic.MageSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

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

  describe "Combustion" do
    test "uses VMangos proc data and spends charges only on fire crits" do
      caster = combustion_caster()
      frostbolt = %Spell{id: 116, school: :frost, dmg_class: 1}
      fireball = %Spell{id: 133, school: :fire, dmg_class: 1}

      caster = SpellFeedback.receive(caster, spell_outcome(:crit), frostbolt, 1_000)
      assert [%{charges: 3}, _visible] = caster.unit.auras
      assert caster.internal.events == []

      caster = SpellFeedback.receive(caster, spell_outcome(:normal), fireball, 1_000)
      assert [%{charges: 3}, _visible] = caster.unit.auras
      assert [%{type: :trigger_spell, spell_id: 28_682}] = caster.internal.events

      caster = %{caster | internal: %{caster.internal | events: []}}
      caster = SpellFeedback.receive(caster, spell_outcome(:crit), fireball, 2_000)
      assert [%{charges: 2}, _visible] = caster.unit.auras
    end

    test "the third fire crit removes both linked auras" do
      caster = combustion_caster(1)
      fireball = %Spell{id: 133, school: :fire, dmg_class: 1}

      caster = SpellFeedback.receive(caster, spell_outcome(:crit), fireball, 1_000)

      assert caster.unit.auras == []
      assert caster.internal.events == []
    end

    test "canceling the visible counter removes the hidden proc aura" do
      caster = combustion_caster()

      {caster, _events} = Aura.cancel_spell(caster, 28_682, 1_000)

      assert caster.unit.auras == []
    end
  end

  defp combustion_caster(charges \\ 3) do
    proc_spell = %Spell{
      id: 11_129,
      script_name: "spell_mage_combustion_proc",
      proc_chance: 100,
      proc_type_mask: 0x00010000,
      proc_rule: %ProcRule{school_mask: Spell.school_mask(:fire)},
      effects: [%Effect{type: :trigger_spell, trigger_spell_id: 28_682}]
    }

    visible_spell = %Spell{id: 28_682, script_name: "spell_mage_combustion_buff"}

    %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        level: 60,
        auras: [
          %Holder{spell: proc_spell, caster_guid: 1, caster_level: 60, charges: charges, slot: 0},
          %Holder{spell: visible_spell, caster_guid: 1, caster_level: 60, slot: 1}
        ]
      },
      internal: %Internal{events: []}
    }
  end

  defp spell_outcome(outcome), do: %{outcome: outcome, victim_guid: 2, proc_type: :deal_harmful_spell}
end
