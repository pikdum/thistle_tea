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
  end

  describe "roll?/1" do
    test "always accepts one hundred percent and rejects zero percent" do
      assert Proc.roll?(%Spell{proc_chance: 100})
      refute Proc.roll?(%Spell{proc_chance: 0})
    end
  end
end
