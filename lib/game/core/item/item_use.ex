defmodule ThistleTea.Game.Core.Item.ItemUse do
  @moduledoc """
  Plans on-use charge consumption and binding. Negative charges destroy one
  item only when exhausted; positive charges leave an empty item behind.
  Checks explicit creature targets against an item's allowed entries and life states,
  and applies an item spell slot's category and cooldown overrides to its spell.
  """
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Item.Enchantments
  alias ThistleTea.Game.Core.Profession.OpenLock
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.SpellTeaching

  def validate_target([], _target), do: :ok

  def validate_target(requirements, %{entity_type: :mob, entry: entry, alive?: alive?}) when is_boolean(alive?) do
    if {entry, alive?} in requirements, do: :ok, else: {:error, :bad_targets}
  end

  def validate_target(_requirements, _target), do: {:error, :bad_targets}

  def deferred_costs?(%Spell{} = spell, cast_item_guid) do
    Enchantments.item_enchant?(spell) or OpenLock.spell?(spell) or
      (is_integer(cast_item_guid) and SpellTeaching.spell?(spell)) or
      Enum.any?(spell.effects, &(&1.type == :summon_change_item))
  end

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

  def with_cooldowns(%Spell{} = spell, %ItemTemplate{} = template, index) do
    category = Map.fetch!(template, :"spellcategory_#{index}")
    cooldown = Map.fetch!(template, :"spellcooldown_#{index}")
    category_cooldown = Map.fetch!(template, :"spellcategorycooldown_#{index}")

    %{
      spell
      | category: if(positive?(category), do: category, else: spell.category),
        recovery_time_ms: if(non_negative?(cooldown), do: cooldown, else: spell.recovery_time_ms),
        category_recovery_time_ms:
          if(non_negative?(category_cooldown), do: category_cooldown, else: spell.category_recovery_time_ms)
    }
  end

  def defer_consumption?(%Cast{cast_time_ms: cast_time_ms} = casting) do
    is_integer(cast_time_ms) and cast_time_ms > 0 and not Cast.channeled?(casting)
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

  defp positive?(value), do: is_integer(value) and value > 0
  defp non_negative?(value), do: is_integer(value) and value >= 0

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
