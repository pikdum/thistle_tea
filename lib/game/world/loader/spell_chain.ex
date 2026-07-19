defmodule ThistleTea.Game.World.Loader.SpellChain do
  @moduledoc """
  Loads VMangos spell rank lineages used for rank replacement and talent-family resolution.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get(spell_id) when is_integer(spell_id) and spell_id > 0 do
    Map.get(get_many([spell_id]), spell_id)
  end

  def get(_spell_id), do: nil

  def get_many(spell_ids) when is_list(spell_ids) do
    spell_ids = spell_ids |> Enum.filter(&(is_integer(&1) and &1 > 0)) |> Enum.uniq()
    {cached, missing} = split_cached(spell_ids)
    loaded = load_many(missing)

    Enum.each(missing, &:ets.insert(__MODULE__, {{:chain, &1}, Map.get(loaded, &1)}))
    Map.merge(cached, loaded)
  end

  def get_many(_spell_ids), do: %{}

  def superseded_by_map(spell_ids) when is_list(spell_ids) do
    spell_ids
    |> get_many()
    |> Enum.flat_map(fn
      {spell_id, %{prev_spell: prev_spell}} when is_integer(prev_spell) and prev_spell > 0 ->
        [{prev_spell, spell_id}]

      _entry ->
        []
    end)
    |> Map.new()
  end

  def superseded_by_map(_spell_ids), do: %{}

  defp split_cached(spell_ids) do
    Enum.reduce(spell_ids, {%{}, []}, fn spell_id, {cached, missing} ->
      case :ets.lookup(__MODULE__, {:chain, spell_id}) do
        [{_key, nil}] -> {cached, missing}
        [{_key, chain}] -> {Map.put(cached, spell_id, chain), missing}
        _missing -> {cached, [spell_id | missing]}
      end
    end)
  end

  defp load_many([]), do: %{}

  defp load_many(spell_ids) do
    rows = Mangos.Repo.all(from(chain in Mangos.SpellChain, where: chain.spell_id in ^spell_ids))

    names =
      rows
      |> Enum.flat_map(&[&1.spell_id, &1.first_spell])
      |> Enum.uniq()
      |> then(fn ids -> DBC.all(from(s in Spell, where: s.id in ^ids, select: {s.id, s.name_en_gb})) end)
      |> Map.new()

    rows
    |> Enum.group_by(& &1.spell_id)
    |> Map.new(fn {spell_id, candidates} ->
      row = select_matching_chain(candidates, names)

      {spell_id, %{first_spell: row.first_spell, rank: row.rank, prev_spell: row.prev_spell, req_spell: row.req_spell}}
    end)
  end

  defp select_matching_chain(rows, names) do
    current_name = Map.get(names, hd(rows).spell_id)

    rows
    |> Enum.filter(&(Map.get(names, &1.first_spell) == current_name))
    |> Enum.max_by(&(&1.rank || 0), fn -> hd(rows) end)
  end
end
