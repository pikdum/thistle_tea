defmodule ThistleTea.Game.World.Loader.Talent do
  @moduledoc """
  Preloads the talent trees from the Talent and TalentTab DBCs: per-class
  tab lists, per-talent tier/column/rank/prerequisite data, and a reverse
  spell-to-talent index so spent points can be derived from the spellbook.
  """
  import Bitwise, only: [<<<: 2, &&&: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData

  @classes 1..11
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    tabs = DBC.all(TalentTab)

    Enum.each(@classes, fn class ->
      class_mask = 1 <<< (class - 1)

      tab_ids =
        tabs
        |> Enum.filter(&((&1.class_mask &&& class_mask) != 0))
        |> Enum.sort_by(& &1.order_index)
        |> Enum.map(& &1.id)

      :ets.insert(__MODULE__, {{:tabs, class}, tab_ids})
    end)

    Talent
    |> DBC.all()
    |> Enum.each(fn row ->
      talent = build(row)
      :ets.insert(__MODULE__, {{:talent, talent.id}, talent})

      talent.rank_spell_ids
      |> Enum.with_index()
      |> Enum.each(fn {spell_id, rank_index} ->
        :ets.insert(__MODULE__, {{:by_spell, spell_id}, {talent.id, talent.tab_id, rank_index}})
      end)
    end)

    :ok
  end

  def get(talent_id) when is_integer(talent_id) and talent_id > 0 do
    case :ets.lookup(__MODULE__, {:talent, talent_id}) do
      [{_key, %TalentData{} = talent}] -> talent
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def get(_talent_id), do: nil

  def tab_ids(class) when is_integer(class) do
    case :ets.lookup(__MODULE__, {:tabs, class}) do
      [{_key, tab_ids}] -> tab_ids
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  def tab_ids(_class), do: []

  def by_spell(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:by_spell, spell_id}) do
      [{_key, entry}] -> entry
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def by_spell(_spell_id), do: nil

  defp build(row) do
    rank_spell_ids =
      [row.spell_rank_0, row.spell_rank_1, row.spell_rank_2, row.spell_rank_3, row.spell_rank_4]
      |> Enum.take_while(&(is_integer(&1) and &1 > 0))

    %TalentData{
      id: row.id,
      tab_id: row.tab,
      tier: row.tier || 0,
      column: row.column_index || 0,
      depends_on: positive(row.prereq_talents_0),
      depends_on_rank: row.prereq_ranks_0 || 0,
      required_spell_id: positive(row.required_spell),
      rank_spell_ids: rank_spell_ids
    }
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil
end
