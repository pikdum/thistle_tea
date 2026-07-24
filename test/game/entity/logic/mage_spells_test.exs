defmodule ThistleTea.Game.Entity.Logic.MageSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
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

  describe "ward reflection talents" do
    test "Improved Fire Ward adds its dummy chance to Fire Ward" do
      talent = %Spell{
        id: 13_043,
        spell_family: 3,
        effects: [%Effect{index: 0, type: :dummy, base_points: 19, die_sides: 1, base_dice: 1}]
      }

      caster = ward_caster(talent)
      ward = ward_spell(543, :fire, 0x8)
      context = CastContext.from_caster(caster, ward, 1)
      {caster, _events} = Aura.apply_spell(caster, context, ward, 1_000)

      assert [%Holder{auras: auras}] = caster.unit.auras
      assert %{amount: 20, misc_value: 0x4} = Enum.find(auras, &(&1.type == :reflect_spells_school))
    end

    test "Frost Warding adds its dummy chance only to Frost Ward" do
      talent = %Spell{
        id: 28_332,
        spell_family: 3,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :add_flat_modifier, base_points: 29},
          %Effect{index: 1, type: :dummy, base_points: 19, die_sides: 1, base_dice: 1}
        ]
      }

      caster = ward_caster(talent)
      fire_ward = ward_spell(543, :fire, 0x8)
      frost_ward = ward_spell(6143, :frost, 0x80100)

      assert CastContext.from_caster(caster, fire_ward, 1).reflect_chance_bonus == 0
      assert CastContext.from_caster(caster, frost_ward, 1).reflect_chance_bonus == 20
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

    test "the final fire crit activates the deferred cooldown" do
      caster = combustion_caster(1)
      [%Holder{spell: proc_spell} = proc_holder, visible] = caster.unit.auras

      proc_spell = %{
        proc_spell
        | attributes: MapSet.new([:cooldown_on_event]),
          category: 1163,
          category_recovery_time_ms: 180_000
      }

      caster = %{caster | unit: %{caster.unit | auras: [%{proc_holder | spell: proc_spell}, visible]}}
      caster = Cooldowns.start(caster, proc_spell, 500)
      assert Cooldowns.on_cooldown?(caster, proc_spell, 500)

      fireball = %Spell{id: 133, school: :fire, dmg_class: 1}
      caster = SpellFeedback.receive(caster, spell_outcome(:crit), fireball, 1_000)

      assert caster.unit.auras == []
      assert Enum.any?(caster.internal.events, &(&1.type == :cooldown_event and &1.spell_id == 11_129))
      assert Cooldowns.on_cooldown?(caster, proc_spell, 1_001)
      refute Cooldowns.on_cooldown?(caster, proc_spell, 181_001)
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

  defp ward_caster(talent) do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{},
      internal: %Internal{spellbook: %{talent.id => talent}}
    }
  end

  defp ward_spell(id, school, family_flags) do
    %Spell{
      id: id,
      school: school,
      spell_family: 3,
      family_flags_0: family_flags,
      duration_ms: 30_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :school_absorb,
          base_points: 164,
          misc_value: Spell.school_mask(school)
        },
        %Effect{
          index: 1,
          type: :apply_aura,
          aura: :reflect_spells_school,
          base_points: -1,
          die_sides: 1,
          base_dice: 1,
          misc_value: Spell.school_mask(school)
        }
      ]
    }
  end

  defp spell_outcome(outcome), do: %{outcome: outcome, victim_guid: 2, proc_type: :deal_harmful_spell}
end
