defmodule ThistleTea.Game.Entity.Logic.Event do
  defstruct [
    :type,
    :source_guid,
    :target_guid,
    :spell_id,
    :school,
    :damage,
    :periodic?,
    :aura_slot,
    :duration_ms
  ]

  def spell_damage(source_guid, target_guid, spell, damage, opts \\ []) do
    %__MODULE__{
      type: :spell_damage,
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell.id,
      school: spell.school,
      damage: damage,
      periodic?: Keyword.get(opts, :periodic?, false)
    }
  end

  def aura_duration(slot, duration_ms) when is_integer(slot) and is_integer(duration_ms) do
    %__MODULE__{
      type: :aura_duration,
      aura_slot: slot,
      duration_ms: duration_ms
    }
  end

  def movement_stopped do
    %__MODULE__{type: :movement_stopped}
  end
end
