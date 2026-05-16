defmodule ThistleTea.Game.Spell.CastContext do
  alias ThistleTea.Game.Entity.Data.Mob

  defstruct [
    :caster_guid,
    :caster_level,
    :caster_type,
    :target_guid,
    :spell
  ]

  def from_caster(%{object: %{guid: guid}, unit: %{level: level}} = caster, spell, target_guid)
      when is_integer(guid) and is_integer(level) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: level,
      caster_type: caster_type(caster),
      target_guid: target_guid,
      spell: spell
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
end
