defmodule ThistleTea.Game.Entity.Logic.Loot do
  @moduledoc """
  Loot state and loot-table rolling: rolls Mangos loot rows (groups, reference
  entries, negative-chance quest drops) into a loot window, and tracks taking
  or returning items and gold from it.
  """

  defmodule Item do
    @moduledoc false
    defstruct [
      :slot,
      :item_id,
      :display_id,
      count: 1,
      quality: 0,
      slot_type: 0,
      looted: false,
      blocked: false,
      quest_item: false
    ]
  end

  defstruct gold: 0, items: []

  @max_items 16
  @max_reference_depth 3

  def empty?(%__MODULE__{gold: gold, items: items}) do
    gold <= 0 and Enum.all?(items, & &1.looted)
  end

  def take_item(%__MODULE__{items: items} = loot, slot) do
    case Enum.find(items, fn item -> item.slot == slot and not item.looted and not item.blocked end) do
      %Item{} = item ->
        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        items = Enum.map(items, fn i -> if i.slot == slot, do: %{i | looted: true}, else: i end)
        {:ok, item, %{loot | items: items}}

      _ ->
        {:error, :already_looted}
    end
  end

  def block_item(%__MODULE__{} = loot, slot), do: set_blocked(loot, slot, true)

  def unblock_item(%__MODULE__{} = loot, slot), do: set_blocked(loot, slot, false)

  defp set_blocked(%__MODULE__{items: items} = loot, slot, blocked?) do
    items = Enum.map(items, fn i -> if i.slot == slot, do: %{i | blocked: blocked?}, else: i end)
    %{loot | items: items}
  end

  def return_item(%__MODULE__{items: items} = loot, slot) do
    items = Enum.map(items, fn i -> if i.slot == slot, do: %{i | looted: false}, else: i end)
    %{loot | items: items}
  end

  def take_gold(%__MODULE__{gold: gold} = loot) when gold > 0 do
    {:ok, gold, %{loot | gold: 0}}
  end

  def take_gold(%__MODULE__{}), do: {:error, :no_gold}

  def roll(rows, get_reference_rows, rand \\ &:rand.uniform/0) do
    rows
    |> roll_rows(get_reference_rows, rand, 0)
    |> Enum.take(@max_items)
  end

  defp roll_rows(_rows, _get_reference_rows, _rand, depth) when depth > @max_reference_depth, do: []

  defp roll_rows(rows, get_reference_rows, rand, depth) do
    {grouped, ungrouped} = Enum.split_with(rows, fn row -> row.groupid > 0 end)

    ungrouped_drops =
      ungrouped
      |> Enum.filter(fn row -> rand.() * 100 < abs(row.chance) end)
      |> Enum.flat_map(fn row -> resolve_row(row, get_reference_rows, rand, depth) end)

    grouped_drops =
      grouped
      |> Enum.group_by(& &1.groupid)
      |> Enum.flat_map(fn {_groupid, group} ->
        case roll_group(group, rand) do
          nil -> []
          row -> resolve_row(row, get_reference_rows, rand, depth)
        end
      end)

    ungrouped_drops ++ grouped_drops
  end

  defp resolve_row(%{mincount_or_ref: ref} = row, get_reference_rows, rand, depth) when ref < 0 do
    reference_rows = get_reference_rows.(-ref)

    Enum.flat_map(1..max(row.maxcount, 1), fn _ ->
      roll_rows(reference_rows, get_reference_rows, rand, depth + 1)
    end)
  end

  defp resolve_row(row, _get_reference_rows, rand, _depth) do
    count = row.mincount_or_ref + trunc(rand.() * (max(row.maxcount, row.mincount_or_ref) - row.mincount_or_ref + 1))
    [{row.item, max(min(count, row.maxcount), row.mincount_or_ref), row.chance < 0}]
  end

  defp roll_group(group, rand) do
    roll = rand.() * 100
    {explicit, equal} = Enum.split_with(group, fn row -> row.chance != 0 end)

    case pick_explicit(explicit, roll) do
      nil -> pick_equal_chanced(equal, rand)
      row -> row
    end
  end

  defp pick_explicit(rows, roll) do
    rows
    |> Enum.reduce_while({roll, nil}, fn row, {remaining, _} ->
      if remaining < abs(row.chance) do
        {:halt, {remaining, row}}
      else
        {:cont, {remaining - abs(row.chance), nil}}
      end
    end)
    |> elem(1)
  end

  defp pick_equal_chanced([], _rand), do: nil

  defp pick_equal_chanced(rows, rand) do
    index = trunc(rand.() * length(rows))
    Enum.at(rows, min(index, length(rows) - 1))
  end
end
