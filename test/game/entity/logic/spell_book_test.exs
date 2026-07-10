defmodule ThistleTea.Game.Entity.Logic.SpellBookTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.SpellBook

  @heroic_strike_chain %{78 => 284, 284 => 285}

  describe "learn/3" do
    test "learns a brand-new spell" do
      assert {[133], [{:learned, 133}]} = SpellBook.learn([], [133], %{})
    end

    test "ignores already-known spells" do
      assert {[133], []} = SpellBook.learn([133], [133], %{})
    end

    test "supersedes the previous rank" do
      assert {[6603, 284], [{:superseded, 78, 284}]} =
               SpellBook.learn([6603, 78], [284], @heroic_strike_chain)
    end

    test "supersedes only the immediate previous rank" do
      assert {[78, 285], [{:learned, 285}]} = SpellBook.learn([78], [285], @heroic_strike_chain)
    end

    test "supersedes within a batch of new ranks" do
      assert {[285], [{:learned, 78}, {:superseded, 78, 284}, {:superseded, 284, 285}]} =
               SpellBook.learn([], [78, 284, 285], @heroic_strike_chain)
    end

    test "orders a batch by supersession instead of numeric spell id" do
      assert {[285], [{:learned, 78}, {:superseded, 78, 284}, {:superseded, 284, 285}]} =
               SpellBook.learn([], [285, 78, 284], @heroic_strike_chain)
    end

    test "repairs lower ranks left beside an already-known higher rank" do
      assert {[285], [{:superseded, 78, 284}, {:removed, 284}]} =
               SpellBook.learn([78, 285], [284, 285], @heroic_strike_chain)
    end

    test "learns stacking ranks side by side" do
      assert {[133, 143], [{:learned, 143}]} = SpellBook.learn([133], [143], %{})
    end
  end
end
