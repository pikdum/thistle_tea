defmodule ThistleTea.Game.Entity.Logic.EquipmentAuras do
  @moduledoc """
  Reconciles passive equipment auras by enchantment or set source. Existing
  holders retain their proc state while their equipment requirements hold.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  def sync(character, enchantments, get_spell, now, set_sources \\ []) do
    previous = character.unit.auras || []
    ordinary = Enum.filter(previous, &is_nil(&1.item_source))
    existing = Map.new(previous, &{&1.item_source, &1})

    enchant_sources =
      for {_slot, item, enchant_slot, enchantment} <- enchantments,
          %{type: 3, spell_id: spell_id} <- enchantment.effects,
          do: {item.object.guid, enchant_slot, spell_id}

    equipped =
      for {_kind, _id, spell_id} = source <- Enum.uniq(enchant_sources ++ set_sources),
          holder = Map.get(existing, source) || build_holder(character, get_spell.(spell_id), source, now),
          not is_nil(holder),
          eligible?(character, holder),
          do: holder

    {character, events} =
      Transition.run(character, %Change{holders: ordinary ++ equipped, cause: :removed, now: now})

    Effects.enqueue(character, events)
  end

  defp eligible?(character, %Holder{item_source: {:item_set, _id, _spell_id}, spell: spell}) do
    Spell.shapeshift_cast_error(spell, character.unit.shapeshift_form || 0) == :ok
  end

  defp eligible?(_character, _holder), do: true

  defp build_holder(character, %Spell{} = spell, source, now) do
    case Application.equipment_holder(character, spell, source, now) do
      %Holder{auras: []} -> nil
      holder -> holder
    end
  end

  defp build_holder(_character, _spell, _source, _now), do: nil
end
