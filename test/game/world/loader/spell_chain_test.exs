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
  @ordinary_rank_2 90_000_021

  setup do
    SpellChain.init()
    Talent.init()

    :ets.insert(SpellChain, {{:chain, @rank_1}, chain(@rank_1, 0, 1)})
    :ets.insert(SpellChain, {{:chain, @rank_2}, chain(@rank_1, @rank_1, 2)})
    :ets.insert(SpellChain, {{:chain, @rank_3}, chain(@rank_1, @rank_2, 3)})
    :ets.insert(SpellChain, {{:chain, @ordinary_spell}, chain(@ordinary_spell, 0, 1)})
    :ets.insert(SpellChain, {{:chain, @ordinary_rank_2}, chain(@ordinary_spell, @ordinary_spell, 2)})
    :ets.insert(Talent, {{:by_spell, @rank_1}, {@talent_id, @talent_tab_id, 0}})

    on_exit(fn ->
      Enum.each([@rank_1, @rank_2, @rank_3, @ordinary_spell, @ordinary_rank_2], fn spell_id ->
        :ets.delete(SpellChain, {:chain, spell_id})
        :ets.delete(Talent, {:by_spell, spell_id})
      end)
    end)

    :ok
  end

  describe "talent rank replacement" do
    test "does not replace ordinary spell ranks from their chain alone" do
      spell_ids = [@rank_1, @rank_2, @rank_3, @ordinary_spell, @ordinary_rank_2]
      superseded_by = Talent.superseded_by_map(spell_ids)

      assert superseded_by == %{@rank_1 => @rank_2, @rank_2 => @rank_3}

      {known_ids, _events} = SpellBook.learn([], spell_ids, superseded_by)
      assert Enum.sort(known_ids) == Enum.sort([@rank_3, @ordinary_spell, @ordinary_rank_2])
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
