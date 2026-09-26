defmodule ThistleTea.Game.World.Loader.SpellGroupDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.StackRules
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellGroup

  @moduletag :dbc_db

  describe "load/1" do
    test "compiled spells inherit rank-root membership and retain exact upgrade lists" do
      ids = [19_740, 19_834]
      groups = :ets.tab2list(SpellGroup)
      chains = for id <- ids, row <- :ets.lookup(SpellChain, {:chain, id}), do: row

      on_exit(fn ->
        :ets.delete_all_objects(SpellGroup)
        :ets.insert(SpellGroup, groups)
        Enum.each(ids, &:ets.delete(SpellChain, {:chain, &1}))
        :ets.insert(SpellChain, chains)
      end)

      :ets.insert(SpellChain, [
        {{:chain, 19_740}, %{first_spell: 19_740, rank: 1}},
        {{:chain, 19_834}, %{first_spell: 19_740, rank: 2}}
      ])

      :ets.insert(SpellGroup, [
        {19_740, %StackRules{groups: %{1002 => 1}}},
        {19_834, %StackRules{weaker: MapSet.new([123])}}
      ])

      spell = SpellLoader.load(19_834)
      assert spell.first_in_chain == 19_740
      assert spell.stack_rules.groups == %{1002 => 1}
      assert spell.stack_rules.weaker == MapSet.new([123])
      assert SpellLoader.build_spellbook(ids)[19_834].stack_rules == spell.stack_rules
    end
  end
end
