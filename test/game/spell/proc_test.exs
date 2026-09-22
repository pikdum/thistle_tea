defmodule ThistleTea.Game.Spell.ProcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule

  describe "eligible?/4" do
    test "cast-end and hit procs remain separate even with always-trigger flags" do
      for rule <- [nil, %ProcRule{proc_ex: 1}, %ProcRule{proc_ex: 0x10000}] do
        spell = %Spell{proc_type_mask: 0x10000, proc_rule: rule}
        assert Proc.eligible?(spell, %Spell{}, :deal_harmful_spell, :normal)
        refute Proc.eligible?(spell, %Spell{}, :deal_harmful_spell, :cast_end)
        refute Proc.eligible?(spell, %Spell{}, :deal_harmful_spell, %{proc_ex: 0x80001})
      end

      for flags <- [0x80000, 0x90000, 0x80001] do
        spell = %Spell{proc_type_mask: 0x10000, proc_rule: %ProcRule{proc_ex: flags}}
        assert Proc.eligible?(spell, %Spell{}, :deal_harmful_spell, :cast_end)

        for outcome <- [:normal, :crit, :miss, :resist] do
          refute Proc.eligible?(spell, %Spell{}, :deal_harmful_spell, outcome)
        end
      end
    end

    test "caster suppression leaves victim-side procs eligible" do
      spell = %Spell{proc_type_mask: 0x30000}
      trigger = %Spell{attributes: MapSet.new([:suppress_caster_procs])}
      refute Proc.eligible?(spell, trigger, :deal_harmful_spell, :normal)
      assert Proc.eligible?(spell, trigger, :take_harmful_spell, :normal)
    end

    test "partial blocks match both normal and block rules even when their damage is absorbed" do
      for mask <- [0x41, 0x441] do
        context = %{outcome: :block, proc_ex: mask}

        for rule <- [nil, %ProcRule{proc_ex: 1}, %ProcRule{proc_ex: 0x40}] do
          assert Proc.eligible?(%Spell{proc_type_mask: 4, proc_rule: rule}, nil, :deal_melee_swing, context)
        end

        refute Proc.eligible?(
                 %Spell{proc_type_mask: 4, proc_rule: %ProcRule{proc_ex: 2}},
                 nil,
                 :deal_melee_swing,
                 context
               )
      end

      full_block = %{outcome: :block, proc_ex: 0x40}
      refute Proc.eligible?(%Spell{proc_type_mask: 4}, nil, :deal_melee_swing, full_block)

      assert Proc.eligible?(
               %Spell{proc_type_mask: 4, proc_rule: %ProcRule{proc_ex: 0x40}},
               nil,
               :deal_melee_swing,
               full_block
             )
    end

    test "absorb-only rules require absorption independently of hit or block" do
      spell = %Spell{proc_type_mask: 8, proc_rule: %ProcRule{proc_ex: 0x400}}

      for mask <- [0x401, 0x402, 0x441] do
        assert Proc.eligible?(spell, nil, :take_melee_swing, %{outcome: :normal, proc_ex: mask})
      end

      for mask <- [1, 2, 0x40, 0x41] do
        refute Proc.eligible?(spell, nil, :take_melee_swing, %{outcome: :normal, proc_ex: mask})
      end
    end

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

    test "ordinary weapon swings satisfy physical school restrictions" do
      for proc_type <- [:deal_melee_swing, :take_melee_swing, :deal_ranged_attack, :take_ranged_attack] do
        for mask <- [1, 5, 127] do
          proc_spell = %Spell{proc_type_mask: 0xCC, proc_rule: %ProcRule{school_mask: mask}}
          assert Proc.eligible?(proc_spell, nil, proc_type, :normal)
          refute Proc.eligible?(proc_spell, nil, proc_type, :miss)
        end

        magic_only = %Spell{proc_type_mask: 0xCC, proc_rule: %ProcRule{school_mask: 4}}
        refute Proc.eligible?(magic_only, nil, proc_type, :normal)
      end
    end

    test "maps ranged attack and ability proc flags on both sides" do
      proc_spell = %Spell{proc_type_mask: 0x3C0}

      assert Proc.eligible?(proc_spell, %Spell{}, :deal_ranged_attack, :normal)
      assert Proc.eligible?(proc_spell, %Spell{}, :take_ranged_attack, :normal)
      assert Proc.eligible?(proc_spell, %Spell{}, :deal_ranged_ability, :crit)
      assert Proc.eligible?(proc_spell, %Spell{}, :take_ranged_ability, :crit)
      refute Proc.eligible?(proc_spell, %Spell{}, :deal_melee_ability, :normal)
    end

    test "requires the VMangos positive-periodic flag for HoT procs" do
      triggering_spell = %Spell{school: :nature}
      periodic_proc = %Spell{proc_rule: %ProcRule{proc_flags: 0x40000, proc_ex: 0x40000}}
      unrestricted_proc = %Spell{proc_type_mask: 0x40000}

      assert Proc.eligible?(periodic_proc, triggering_spell, :deal_helpful_periodic, :normal)
      refute Proc.eligible?(periodic_proc, triggering_spell, :deal_harmful_periodic, :normal)
      refute Proc.eligible?(unrestricted_proc, triggering_spell, :deal_helpful_periodic, :normal)
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
