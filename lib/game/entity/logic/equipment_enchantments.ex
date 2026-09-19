defmodule ThistleTea.Game.Entity.Logic.EquipmentEnchantments do
  @moduledoc """
  Reconciles enchantment equip spells by item and enchantment slot. Identical
  enchants on different items remain independent passive aura sources.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  def sync(character, enchantments, get_spell, now) do
    previous = character.unit.auras || []
    ordinary = Enum.filter(previous, &is_nil(&1.item_source))
    existing = Map.new(previous, &{&1.item_source, &1})

    equipped =
      for {_slot, item, enchant_slot, enchantment} <- enchantments,
          %{type: 3, spell_id: spell_id} <- enchantment.effects,
          source = {item.object.guid, enchant_slot, spell_id},
          holder = Map.get(existing, source) || build_holder(character, get_spell.(spell_id), source, now),
          not is_nil(holder),
          do: holder

    {character, events} =
      Transition.run(character, %Change{holders: ordinary ++ equipped, cause: :removed, now: now})

    Effects.enqueue(character, events)
  end

  defp build_holder(character, %Spell{} = spell, source, now) do
    case Application.equipment_holder(character, spell, source, now) do
      %Holder{auras: []} -> nil
      holder -> holder
    end
  end

  defp build_holder(_character, _spell, _source, _now), do: nil
end
