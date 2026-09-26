defmodule ThistleTea.Game.Entity.Logic.Aura.ClassScript do
  @moduledoc """
  Resolves override-class-script procs that require rules beyond the spell's
  proc mask. Target facts come from the target owner's resolved spell feedback.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @blizzard_chill %{836 => 12_484, 988 => 12_485, 989 => 12_486}
  @rejuvenation_power %{0 => 28_722, 1 => 28_723, 3 => 28_724}

  def events(holder, owner_guid, context, roll \\ &:rand.uniform/0)

  def events(%Holder{} = holder, owner_guid, %{victim_guid: victim, victim_alive?: true} = context, roll)
      when is_integer(victim) do
    Enum.flat_map(holder.auras, fn
      %Aura{type: :override_class_scripts} = aura ->
        case trigger(aura, context, roll) do
          nil ->
            []

          spell_id ->
            [
              Effects.trigger_spell(owner_guid, holder.caster_level || 1, victim, spell_id,
                cast_item_guid: holder.cast_item_guid,
                triggered_by_spell_id: holder.spell.id
              )
            ]
        end

      _aura ->
        []
    end)
  end

  def events(_holder, _owner_guid, _context, _roll), do: []

  defp trigger(%Aura{misc_value: 4309}, _context, _roll), do: 17_941

  defp trigger(%Aura{misc_value: script}, %{spell: %Spell{spell_visual: 259}}, _roll)
       when is_map_key(@blizzard_chill, script), do: Map.fetch!(@blizzard_chill, script)

  defp trigger(%Aura{misc_value: script, amount: chance}, _context, roll)
       when script in [4086, 4087] and is_number(chance) and chance > 0 do
    if chance >= 100 or roll.() * 100 <= chance, do: 24_406
  end

  defp trigger(%Aura{misc_value: 3656}, %{spell: %Spell{effects: effects}}, _roll) do
    if Enum.any?(effects, &(&1.type == :heal)), do: 23_402
  end

  defp trigger(%Aura{misc_value: 4533}, %{spell: %Spell{} = spell, victim_power_type: power_type}, _roll) do
    if Spell.family_flag?(spell, 7, 0x10), do: Map.get(@rejuvenation_power, power_type)
  end

  defp trigger(%Aura{misc_value: 4537}, %{spell: %Spell{} = spell}, _roll) do
    if Spell.family_flag?(spell, 7, 0x40), do: 28_750
  end

  defp trigger(_aura, _context, _roll), do: nil
end
