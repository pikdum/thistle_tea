defmodule ThistleTea.Game.Entity.Logic.ItemUse do
  @moduledoc """
  Plans on-use charge consumption and binding. Negative charges destroy one
  item only when exhausted; positive charges leave an empty item behind.
  """
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch

  def on_use_spell(%Item{} = item) do
    template = Item.template(item)

    index =
      Enum.find(
        1..5,
        &(Map.fetch!(template, :"spellid_#{&1}") > 0 and Map.fetch!(template, :"spelltrigger_#{&1}") == 0)
      )

    if index do
      spell_id = Map.fetch!(template, :"spellid_#{index}")

      case available(item, index) do
        :ok -> {:ok, spell_id, index, needs_commit?(template)}
        {:error, reason} -> {:cast_error, spell_id, reason}
      end
    else
      {:error, :item_not_found}
    end
  end

  def plan(%Batch{} = batch, %Item{} = item, index) do
    with :ok <- available(item, index) do
      {updated, expendable?, exhausted?} = Enum.reduce(1..5, {item, false, false}, &spend_charge/2)
      updated = Item.bind_on_use(updated)

      cond do
        expendable? and exhausted? -> {:ok, Batch.remove_item(batch, item.object.guid, 1)}
        updated != item -> {:ok, Batch.update(batch, updated)}
        true -> {:ok, batch}
      end
    end
  end

  defp available(item, index) do
    if Map.fetch!(Item.template(item), :"spellcharges_#{index}") != 0 and Item.spell_charge(item, index) == 0,
      do: {:error, :no_charges_remain},
      else: :ok
  end

  defp needs_commit?(template) do
    template.bonding == 3 or Enum.any?(1..5, &(Map.fetch!(template, :"spellcharges_#{&1}") != 0))
  end

  defp spend_charge(index, {item, expendable?, exhausted?}) do
    template = Item.template(item)
    initial = Map.fetch!(template, :"spellcharges_#{index}")

    if initial != 0 and Map.fetch!(template, :"spellid_#{index}") > 0 do
      remaining = toward_zero(Item.spell_charge(item, index))
      item = if template.stackable < 2, do: Item.put_spell_charge(item, index, remaining), else: item
      {item, expendable? or initial < 0, remaining == 0}
    else
      {item, expendable?, exhausted?}
    end
  end

  defp toward_zero(value) when value < 0, do: value + 1
  defp toward_zero(value) when value > 0, do: value - 1
  defp toward_zero(0), do: 0
end
