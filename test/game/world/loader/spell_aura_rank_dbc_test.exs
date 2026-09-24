defmodule ThistleTea.Game.World.Loader.SpellAuraRankDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db
  @fortitude [1243, 1244, 1245, 2791, 10_937, 10_938]
  @prayer [21_562, 21_564]
  @devotion [465, 10_290, 643, 10_291, 1032, 10_292, 10_293]

  setup do
    ids = @fortitude ++ @prayer ++ @devotion ++ [10_909]
    saved_abilities = :ets.match_object(SpellChain, {{:ability_chain, :_}, :_})

    saved =
      for id <- ids,
          {table, key} <- [{SpellChain, {:chain, id}}, {SpellLoader, {:spell, id}}],
          do: {table, key, :ets.lookup(table, key)}

    Enum.each(ids, &:ets.insert(SpellChain, {{:chain, &1}, nil}))

    for ranks <- [@fortitude, @prayer], {id, index} <- Enum.with_index(ranks) do
      chain = %{
        first_spell: hd(ranks),
        prev_spell: if(index > 0, do: Enum.at(ranks, index - 1), else: 0),
        rank: index + 1,
        req_spell: 0
      }

      :ets.insert(SpellChain, {{:chain, id}, chain})
    end

    SpellChain.load_abilities()

    on_exit(fn ->
      :ets.match_delete(SpellChain, {{:ability_chain, :_}, :_})
      :ets.insert(SpellChain, saved_abilities)

      for {table, key, entries} <- saved do
        :ets.delete(table, key)
        :ets.insert(table, entries)
      end
    end)

    :ok
  end

  describe "load/1 and build_spellbook/1" do
    test "retain real buff predecessors, level limits and low-level exceptions" do
      book = SpellLoader.build_spellbook(@fortitude ++ @prayer ++ @devotion)

      for {id, spell} <- book do
        loaded = SpellLoader.load(id)
        assert loaded.rank == spell.rank
        assert loaded.previous_in_chain == spell.previous_in_chain
        :ets.insert(SpellLoader, {{:spell, id}, spell})
      end

      assert SpellLoader.aura_rank(book[10_938], 1).id == 1243
      assert SpellLoader.aura_rank(book[10_938], 2).id == 1244
      assert SpellLoader.aura_rank(book[10_938], 49).id == 10_937
      assert SpellLoader.aura_rank(book[10_938], 50).id == 10_938
      assert SpellLoader.aura_rank(book[21_564], 37) == nil
      assert SpellLoader.aura_rank(book[21_564], 38).id == 21_562
      assert SpellLoader.aura_rank(book[10_293], 1).id == 10_290
      assert SpellLoader.aura_rank(book[10_293], 10).id == 643
      assert book[10_293].rank == 7
      assert AuraRank.minimum_level(book[10_293]) == 50
      assert Spell.attribute?(SpellLoader.load(10_909), :allow_low_level_buff)
    end
  end
end
