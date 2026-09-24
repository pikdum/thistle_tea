defmodule ThistleTea.Game.Spell.RankChainTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell.RankChain

  describe "from_successors/1" do
    test "builds ordered ancestry independently of row order and duplicates" do
      chains = RankChain.from_successors([{2, 3}, {1, 2}, {5, 6}, {1, 2}])
      assert chains[1] == %{first_spell: 1, prev_spell: 0, rank: 1, req_spell: 0}
      assert chains[3] == %{first_spell: 1, prev_spell: 2, rank: 3, req_spell: 0}
      assert chains[6] == %{first_spell: 5, prev_spell: 5, rank: 2, req_spell: 0}
    end

    test "ignores cyclic lineages without dropping valid chains" do
      chains = RankChain.from_successors([{1, 2}, {2, 1}, {2, 3}, {4, 5}])
      assert Map.keys(chains) |> Enum.sort() == [4, 5]
    end
  end
end
