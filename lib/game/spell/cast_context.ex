defmodule ThistleTea.Game.Spell.CastContext do
  alias ThistleTea.Game.Entity.Data.Mob

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  defstruct [
    :caster_guid,
    :caster_level,
    :caster_type,
    :target_guid,
    :spell,
    spell_damage_bonus: %{},
    healing_bonus: 0
  ]

  def from_caster(%{object: %{guid: guid}, unit: %{level: level}} = caster, spell, target_guid)
      when is_integer(guid) and is_integer(level) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: level,
      caster_type: caster_type(caster),
      target_guid: target_guid,
      spell: spell,
      spell_damage_bonus: spell_damage_bonus(caster),
      healing_bonus: healing_bonus(caster)
    }
  end

  def from_caster(%{object: %{guid: guid}} = caster, spell, target_guid) when is_integer(guid) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: 1,
      caster_type: caster_type(caster),
      target_guid: target_guid,
      spell: spell
    }
  end

  defp caster_type(%ThistleTea.Character{}), do: :player
  defp caster_type(%Mob{}), do: :mob
  defp caster_type(_), do: nil

  defp spell_damage_bonus(caster) do
    bonuses = equipment_bonuses(caster)
    Map.new(@schools, fn school -> {school, Map.get(bonuses, :"spell_#{school}", 0)} end)
  end

  defp healing_bonus(caster) do
    caster |> equipment_bonuses() |> Map.get(:healing, 0)
  end

  defp equipment_bonuses(%{internal: %{equipment_bonuses: %{} = bonuses}}), do: bonuses
  defp equipment_bonuses(_caster), do: %{}
end
