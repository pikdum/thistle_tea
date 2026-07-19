defmodule ThistleTea.Game.World.Loader.SpellRankReplacementDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db
  @flamestrike_ranks [2120, 2121, 8422, 8423, 10_215, 10_216]
  @sinister_strike_ranks [1752, 1757, 1758, 1759, 1760, 8621, 11_293, 11_294]
  @heroic_strike_ranks [78, 284, 285, 1608, 11_564, 11_565, 11_566, 11_567, 25_286]

  setup do
    chain_entries =
      @flamestrike_ranks
      |> Enum.with_index()
      |> Enum.map(fn {spell_id, index} ->
        prev_spell = if index > 0, do: Enum.at(@flamestrike_ranks, index - 1), else: 0
        {{:chain, spell_id}, chain(List.first(@flamestrike_ranks), prev_spell, index + 1)}
      end)

    nil_entries = Enum.map(@sinister_strike_ranks ++ @heroic_strike_ranks, &{{:chain, &1}, nil})
    entries = chain_entries ++ nil_entries
    previous = Map.new(entries, fn {key, _value} -> {key, :ets.lookup(SpellChain, key)} end)
    :ets.insert(SpellChain, entries)

    on_exit(fn -> restore_cache(previous) end)
    :ok
  end

  describe "superseded_by_map/1" do
    test "keeps every Flamestrike rank" do
      superseded_by = SpellLoader.superseded_by_map(@flamestrike_ranks)

      assert superseded_by == %{}
      assert {@flamestrike_ranks, events} = SpellBook.learn([], @flamestrike_ranks, superseded_by)
      assert Enum.map(events, fn {:learned, spell_id} -> spell_id end) == @flamestrike_ranks
    end

    test "replaces rogue and warrior ability ranks" do
      assert highest_rank(@sinister_strike_ranks) == 11_294
      assert highest_rank(@heroic_strike_ranks) == 25_286
    end
  end

  defp highest_rank(ranks) do
    superseded_by = SpellLoader.superseded_by_map(ranks)
    {[highest_rank], _events} = SpellBook.learn([], ranks, superseded_by)
    highest_rank
  end

  defp chain(first_spell, prev_spell, rank) do
    %{first_spell: first_spell, prev_spell: prev_spell, rank: rank, req_spell: 0}
  end

  defp restore_cache(previous) do
    Enum.each(previous, fn {key, entries} ->
      :ets.delete(SpellChain, key)

      if entries != [] do
        :ets.insert(SpellChain, entries)
      end
    end)
  end
end
