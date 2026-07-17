defmodule ThistleTea.Game.SpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "harmful?/1" do
    test "damage effects are harmful" do
      spell = %Spell{effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]}
      assert Spell.harmful?(spell)
    end

    test "enemy-targeted debuffs are harmful" do
      spell = %Spell{effects: [%Effect{type: :apply_aura, implicit_target_a: :target_enemy}]}
      assert Spell.harmful?(spell)
    end

    test "heals and ally buffs are not harmful" do
      heal = %Spell{effects: [%Effect{type: :heal, implicit_target_a: :target_ally}]}
      buff = %Spell{effects: [%Effect{type: :apply_aura, implicit_target_a: :target_ally}]}

      refute Spell.harmful?(heal)
      refute Spell.harmful?(buff)
    end
  end

  describe "school_mask/1" do
    test "returns bit masks for spell schools" do
      assert Spell.school_mask(:physical) == 1
      assert Spell.school_mask(:frost) == 16
      assert Spell.school_mask(%Spell{school: :arcane}) == 64
    end

    test "returns zero for unknown school data" do
      assert Spell.school_mask(nil) == 0
    end
  end

  describe "breaks_on_damage?/1" do
    test "derives breakable control from DBC aura interrupt flags" do
      assert Spell.breaks_on_damage?(%Spell{aura_interrupt_flags: 0x2})
      refute Spell.breaks_on_damage?(%Spell{aura_interrupt_flags: 0x4})
    end
  end

  describe "duration_for_combo_points/2" do
    test "interpolates the DBC base and maximum durations across five points" do
      spell = %Spell{duration_ms: 6_000, max_duration_ms: 16_000}

      assert Spell.duration_for_combo_points(spell, 1) == 8_000
      assert Spell.duration_for_combo_points(spell, 3) == 12_000
      assert Spell.duration_for_combo_points(spell, 5) == 16_000
      assert Spell.duration_for_combo_points(spell, 8) == 16_000
    end
  end

  describe "procs_on?/2" do
    test "matches DBC proc-type flags" do
      blade_flurry = %Spell{proc_type_mask: 0x14}

      assert Spell.procs_on?(blade_flurry, :deal_melee_swing)
      assert Spell.procs_on?(blade_flurry, :deal_melee_ability)
      refute Spell.procs_on?(%Spell{}, :deal_melee_swing)
    end
  end

  describe "family_flag?/4" do
    test "matches the requested DBC family-mask word" do
      spell = %Spell{spell_family: 5, family_flags_0: 0x4, family_flags_1: 0x1}

      assert Spell.family_flag?(spell, 5, 0x4)
      assert Spell.family_flag?(spell, 5, 0x1, 1)
      refute Spell.family_flag?(spell, 8, 0x4)
      refute Spell.family_flag?(spell, 5, 0x2)
    end
  end

  describe "vmangos_script?/2" do
    test "matches only the script label carried by the spell" do
      spell = %Spell{script_name: "spell_rogue_vanish"}

      assert Spell.vmangos_script?(spell, "spell_rogue_vanish")
      refute Spell.vmangos_script?(spell, "spell_rogue_eviscerate")
      refute Spell.vmangos_script?(%Spell{}, "spell_rogue_vanish")
    end
  end

  describe "Event.trigger_spell/5" do
    test "carries data-driven custom effect points" do
      event = Event.trigger_spell(1, 60, 2, 25_503, effect_index: 0, base_points: -27)

      assert event.slot == 0
      assert event.amount == -27
    end
  end

  describe "school_index/1" do
    test "returns packet indexes for spell schools" do
      assert Spell.school_index(:physical) == 0
      assert Spell.school_index(:frost) == 4
      assert Spell.school_index(%Spell{school: :arcane}) == 6
    end

    test "preserves integer school values" do
      assert Spell.school_index(7) == 7
    end
  end
end
