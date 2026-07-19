defmodule ThistleTea.Game.World.Loader.SpellChainTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Entity.Logic.Talents
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.Talent

  @talent_id 90_000_001
  @talent_tab_id 90_000_002
  @rank_1 90_000_011
  @rank_2 90_000_012
  @rank_3 90_000_013
  @ordinary_spell 90_000_020

  setup do
    SpellChain.init()
    Talent.init()

    :ets.insert(SpellChain, {{:chain, @rank_1}, chain(@rank_1, 0, 1)})
    :ets.insert(SpellChain, {{:chain, @rank_2}, chain(@rank_1, @rank_1, 2)})
    :ets.insert(SpellChain, {{:chain, @rank_3}, chain(@rank_1, @rank_2, 3)})
    :ets.insert(SpellChain, {{:chain, @ordinary_spell}, nil})
    :ets.insert(Talent, {{:by_spell, @rank_1}, {@talent_id, @talent_tab_id, 0}})

    on_exit(fn ->
      Enum.each([@rank_1, @rank_2, @rank_3, @ordinary_spell], fn spell_id ->
        :ets.delete(SpellChain, {:chain, spell_id})
        :ets.delete(Talent, {:by_spell, spell_id})
      end)
    end)

    :ok
  end

  describe "superseded_by_map/1" do
    test "uses VMangos chain predecessors for rank replacement" do
      superseded_by = SpellChain.superseded_by_map([@rank_1, @rank_2, @rank_3])

      assert superseded_by == %{@rank_1 => @rank_2, @rank_2 => @rank_3}
      assert {[@rank_3], _events} = SpellBook.learn([@rank_1], [@rank_2, @rank_3], superseded_by)
    end
  end

  describe "talent spell lineage" do
    test "trained ranks inherit the talent identity of their predecessor" do
      assert Talent.by_spell(@rank_2) == {@talent_id, @talent_tab_id, 0}
      assert Talent.by_spell(@rank_3) == {@talent_id, @talent_tab_id, 0}
      assert Talents.spent_points([@rank_3]) == 1
    end

    test "debug grants require an already known rank from the talent family" do
      candidates = [@rank_2, @rank_3, @ordinary_spell]

      assert ClassSpell.grantable_spell_ids(candidates, []) == [@ordinary_spell]
      assert ClassSpell.grantable_spell_ids(candidates, [@rank_1]) == candidates
      assert ClassSpell.grantable_spell_ids(candidates, [@rank_2]) == candidates
    end
  end

  defp chain(first_spell, prev_spell, rank) do
    %{first_spell: first_spell, prev_spell: prev_spell, rank: rank, req_spell: 0}
  end
end
