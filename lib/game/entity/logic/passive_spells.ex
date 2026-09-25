defmodule ThistleTea.Game.Entity.Logic.PassiveSpells do
  @moduledoc "Restores eligible learned passives through the shared aura application path."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Environment
  alias ThistleTea.Game.Spell.Passive

  def restore(character, now, scope \\ :all)

  def restore(%Character{internal: %{spellbook: spellbook, taxi_flight: nil}} = character, now, scope)
      when is_map(spellbook) and is_integer(now) do
    if Death.alive?(character) do
      spellbook
      |> spells()
      |> Enum.filter(&in_scope?(&1, scope))
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce({character, []}, &restore_spell(&1, &2, now))
    else
      {character, []}
    end
  end

  def restore(character, _now, _scope), do: {character, []}

  defp restore_spell(spell, {character, events}, now) do
    if Passive.eligible?(spell, character.unit.shapeshift_form, character.internal.outdoors?) and
         not Aura.has_spell?(character, spell.id) do
      {character, applied} = Aura.apply_spell(character, character.object.guid, character.unit.level || 1, spell, now)
      {character, events ++ applied}
    else
      {character, events}
    end
  end

  def removed_ids(previous, current) do
    Enum.map(spells(previous), & &1.id) -- Enum.map(spells(current), & &1.id)
  end

  defp spells(spellbook) do
    (spellbook || %{})
    |> Map.values()
    |> Enum.flat_map(&with_dependencies/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp with_dependencies(%Spell{passive_dependencies: dependencies} = spell),
    do: [spell | Enum.flat_map(dependencies, &with_dependencies/1)]

  defp in_scope?(_spell, :all), do: true
  defp in_scope?(spell, :form), do: Passive.form_dependent?(spell)
  defp in_scope?(spell, :outdoors), do: Environment.outdoor_passive?(spell)
end
