defmodule ThistleTea.Game.Entity.Logic.EquipmentSpells do
  @moduledoc """
  Identifies on-equip spell sources and assigns each effect to either the
  canonical equipment-stat aggregate or a source-owned passive aura holder.
  """

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @stat_auras [
    :mod_damage_done,
    :mod_healing_done,
    :mod_flat_spell_damage_versus,
    :mod_damage_done_creature,
    :mod_attack_power,
    :mod_ranged_attack_power,
    :mod_target_resistance,
    :mod_ranged_haste,
    :mod_shield_block_value,
    :mod_block_percent
  ]

  def sources(items) do
    for %Item{} = item <- items,
        spell_id <- spell_ids(Item.template(item)),
        do: {:item_equip, item.object.guid, spell_id}
  end

  def spell_ids(%ItemTemplate{} = template) do
    [
      {template.spellid_1, template.spelltrigger_1},
      {template.spellid_2, template.spelltrigger_2},
      {template.spellid_3, template.spelltrigger_3},
      {template.spellid_4, template.spelltrigger_4},
      {template.spellid_5, template.spelltrigger_5}
    ]
    |> Enum.flat_map(fn
      {id, 1} when is_integer(id) and id > 0 -> [id]
      _ -> []
    end)
    |> Enum.uniq()
  end

  def eligible?(%Spell{} = spell, form), do: Spell.shapeshift_cast_error(spell, form || 0) == :ok
  def eligible?(_spell, _form), do: false

  def aura_spell(%Spell{} = spell), do: %{spell | effects: Enum.reject(spell.effects, &stat_effect?/1)}
  def aura_spell(_spell), do: nil

  defp stat_effect?(%Effect{type: :apply_aura, aura: aura}), do: aura in @stat_auras
  defp stat_effect?(_effect), do: false
end
