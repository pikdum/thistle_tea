defmodule ThistleTea.Game.Spell.DiminishingReturnsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.DiminishingReturns
  alias ThistleTea.Game.Spell.Effect

  describe "group/2" do
    test "uses spell and effect mechanics in vanilla priority order" do
      assert DiminishingReturns.group(%Spell{mechanic: 17}) == :polymorph
      assert DiminishingReturns.group(%Spell{mechanic: 7, effects: [%Effect{mechanic: 12}]}) == :controlled_stun
      assert DiminishingReturns.group(%Spell{effects: [%Effect{mechanic: 30}]}) == :knockout
      assert DiminishingReturns.group(%Spell{mechanic: 11}) == nil
    end

    test "separates aura-triggered control and preserves charge stuns" do
      assert DiminishingReturns.group(%Spell{mechanic: 12}, true) == :triggered_stun
      assert DiminishingReturns.group(%Spell{mechanic: 7}, true) == :triggered_root
      assert DiminishingReturns.group(%Spell{id: 7922, mechanic: 12}, true) == :controlled_stun
      assert DiminishingReturns.group(%Spell{id: 20_615, mechanic: 12}, true) == :controlled_stun
      assert DiminishingReturns.group(%Spell{id: 12_355, mechanic: 12}) == :triggered_stun
      assert DiminishingReturns.group(%Spell{id: 18_093, mechanic: 12}) == :triggered_stun
    end

    test "honors family exceptions across ranks" do
      assert DiminishingReturns.group(%Spell{spell_family: 8, family_flags_0: 0x00200000, mechanic: 12}) ==
               :kidney_shot

      assert DiminishingReturns.group(%Spell{spell_family: 8, family_flags_0: 0x01000000, mechanic: 5}) == nil
      assert DiminishingReturns.group(%Spell{spell_family: 3, spell_visual: 4325, mechanic: 12}) == nil
      assert DiminishingReturns.group(%Spell{spell_family: 9, family_flags_0: 8}) == :freeze
      assert DiminishingReturns.group(%Spell{spell_family: 11, family_flags_0: 0x80000000}) == :controlled_root
      assert DiminishingReturns.group(%Spell{spell_family: 5, id: 6358, mechanic: 1}) == :warlock_fear

      assert DiminishingReturns.group(%Spell{spell_family: 5, family_flags_0: 0x80000000, mechanic: 5}) ==
               :warlock_fear

      assert DiminishingReturns.group(%Spell{spell_family: 5, family_flags_0: 0x80000000, mechanic: 11}) == nil
      assert DiminishingReturns.group(%Spell{spell_family: 4, family_flags_0: 2, mechanic: 11}) == nil
    end
  end

  describe "scope/1" do
    test "stuns affect creatures and other groups apply in PvP" do
      for group <- [:controlled_stun, :triggered_stun, :kidney_shot] do
        assert DiminishingReturns.scope(group) == :all
      end

      assert DiminishingReturns.scope(:polymorph) == :pvp
      assert DiminishingReturns.scope(nil) == :none
    end
  end
end
