defmodule ThistleTea.Game.Spell.ProcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule

  describe "eligible?/4" do
    test "applies VMangos school restrictions to a DBC proc flag" do
      proc_spell = %Spell{
        proc_type_mask: 0x00010000,
        proc_rule: %ProcRule{school_mask: Spell.school_mask(:fire)}
      }

      assert Proc.eligible?(proc_spell, %Spell{school: :fire}, :deal_harmful_spell, :normal)
      refute Proc.eligible?(proc_spell, %Spell{school: :frost}, :deal_harmful_spell, :normal)
    end

    test "requires matching family masks when VMangos provides them" do
      proc_spell = %Spell{
        proc_type_mask: 0x00010000,
        proc_rule: %ProcRule{spell_family: 3, family_mask_1: 0x4}
      }

      assert Proc.eligible?(
               proc_spell,
               %Spell{school: :fire, spell_family: 3, family_flags_1: 0x4},
               :deal_harmful_spell,
               :crit
             )

      refute Proc.eligible?(
               proc_spell,
               %Spell{school: :fire, spell_family: 3, family_flags_1: 0x8},
               :deal_harmful_spell,
               :crit
             )
    end

    test "honors normal-hit and critical-hit proc-ex masks" do
      proc_spell = %Spell{proc_type_mask: 0x00010000, proc_rule: %ProcRule{proc_ex: 0x2}}

      assert Proc.eligible?(proc_spell, %Spell{school: :fire}, :deal_harmful_spell, :crit)
      refute Proc.eligible?(proc_spell, %Spell{school: :fire}, :deal_harmful_spell, :normal)
    end

    test "maps DBC outgoing melee proc flags" do
      proc_spell = %Spell{proc_type_mask: 0x14}

      assert Proc.eligible?(proc_spell, nil, :deal_melee_swing, :normal)
      assert Proc.eligible?(proc_spell, %Spell{}, :deal_melee_ability, :crit)
      refute Proc.eligible?(proc_spell, nil, :take_melee_swing, :normal)
    end

    test "maps ranged attack and ability proc flags on both sides" do
      proc_spell = %Spell{proc_type_mask: 0x3C0}

      assert Proc.eligible?(proc_spell, %Spell{}, :deal_ranged_attack, :normal)
      assert Proc.eligible?(proc_spell, %Spell{}, :take_ranged_attack, :normal)
      assert Proc.eligible?(proc_spell, %Spell{}, :deal_ranged_ability, :crit)
      assert Proc.eligible?(proc_spell, %Spell{}, :take_ranged_ability, :crit)
      refute Proc.eligible?(proc_spell, %Spell{}, :deal_melee_ability, :normal)
    end
  end

  describe "roll?/3" do
    test "always accepts one hundred percent and rejects zero percent" do
      assert Proc.roll?(%Spell{proc_chance: 100})
      refute Proc.roll?(%Spell{proc_chance: 0})
    end

    test "converts VMangos PPM rates using weapon speed" do
      spell = %Spell{proc_chance: 100, proc_rule: %ProcRule{ppm_rate: 5.0}}

      assert Proc.roll?(spell, 2_000, fn -> 0.1 end)
      refute Proc.roll?(spell, 2_000, fn -> 0.2 end)
      refute Proc.roll?(spell, nil, fn -> 0.0 end)
    end

    test "prefers VMangos custom chance over DBC chance" do
      spell = %Spell{proc_chance: 100, proc_rule: %ProcRule{custom_chance: 10.0}}

      assert Proc.roll?(spell, nil, fn -> 0.05 end)
      refute Proc.roll?(spell, nil, fn -> 0.2 end)
    end
  end
end
