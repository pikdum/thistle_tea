defmodule ThistleTea.Game.Core.Spell.StackRulesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.StackRules

  describe "compile/3" do
    test "selects build ranges and the latest eligible rule" do
      members = [member(1, 20, 5), member(1, 10, 8), %{member(1, 30, 9) | build_min: 6000}]
      rules = [rule(1, 1, 0), rule(1, 3, 5000), rule(1, 0, 6000)]
      compiled = StackRules.compile(members, rules, 5875)
      assert Map.keys(compiled) |> Enum.sort() == [10, 20]
      assert StackRules.relation(spell(20, compiled), spell(10, compiled)) == :replace
      assert StackRules.relation(spell(10, compiled), spell(20, compiled)) == :block
      assert compiled[20].stronger == MapSet.new([10])
      assert compiled[10].weaker == MapSet.new([20])
      earlier = StackRules.compile(members, rules, 4000)
      assert StackRules.relation(spell(10, earlier), spell(20, earlier)) == :replace
    end

    test "expands nested groups without looping or inventing missing members" do
      members = [member(1, -2), member(2, -1), member(2, -99), member(2, 10), member(1, 20)]
      compiled = StackRules.compile(members, [rule(1, 1)], 5875)
      assert compiled[10].groups == %{1 => 1, 2 => 0}
      assert compiled[20].groups == %{1 => 1, 2 => 0}
      assert StackRules.relation(spell(10, compiled), spell(20, compiled)) == :replace
    end

    test "the first non-default common group determines exclusivity" do
      members = for id <- [1, 2, 3], spell <- [10, 20], do: member(id, spell, spell)
      compiled = StackRules.compile(members, [rule(1, 0), rule(2, 1), rule(3, 3)], 5875)
      assert StackRules.relation(spell(10, compiled), spell(20, compiled)) == :replace
      assert StackRules.relation(spell(20, compiled), spell(10, compiled)) == :replace
    end
  end

  describe "inherit/2" do
    test "ranks inherit membership while preserving their explicit upgrade order" do
      compiled = StackRules.compile([member(1, 10, 0), member(1, 11, 2), member(1, 20, 1)], [rule(1, 3)], 5875)
      higher = %{spell(11, compiled) | first_in_chain: 10, stack_rules: StackRules.inherit(compiled[11], compiled[10])}
      assert StackRules.relation(spell(20, compiled), higher) == :replace
      assert StackRules.relation(higher, spell(20, compiled)) == :block
      assert higher.stack_rules.weaker == MapSet.new([10, 20])
    end
  end

  describe "relation/2" do
    test "ordinary exclusivity preserves existing passive and hidden auras from other chains" do
      compiled = StackRules.compile([member(1, 10), member(1, 20)], [rule(1, 1)], 5875)

      for attribute <- [:passive, :do_not_display] do
        passive = %{spell(10, compiled) | attributes: MapSet.new([attribute])}
        assert StackRules.relation(passive, spell(20, compiled)) == :none
      end
    end

    test "same spells refresh and direct trigger pairs preserve their parent" do
      compiled = StackRules.compile([member(1, 10), member(1, 20)], [rule(1, 1)], 5875)
      parent = %{spell(10, compiled) | effects: [%Effect{trigger_spell_id: 20}]}
      child = spell(20, compiled)
      assert StackRules.relation(parent, child) == :none
      assert StackRules.relation(child, parent) == :none
      assert StackRules.relation(child, child) == :none
    end

    test "ordinary group membership does not override same-chain rank handling" do
      compiled = StackRules.compile([member(1, 10), member(1, 20)], [rule(1, 1)], 5875)
      lower = %{spell(10, compiled) | first_in_chain: 10}
      higher = %{spell(20, compiled) | first_in_chain: 10}
      assert StackRules.relation(lower, higher) == :none
    end
  end

  defp member(group, spell, order \\ 0),
    do: %{group_id: group, spell_id: spell, group_spell_id: order, build_min: 0, build_max: 5875}

  defp rule(group, rule, build \\ 0), do: %{group_id: group, stack_rule: rule, build: build}
  defp spell(id, compiled), do: %Spell{id: id, stack_rules: Map.fetch!(compiled, id)}
end
