defmodule ThistleTea.Game.Entity.Logic.Event do
  defstruct [
    :type,
    :source_guid,
    :source_level,
    :target_guid,
    :spell_id,
    :school,
    :damage,
    :periodic?,
    :aura_slot,
    :duration_ms,
    :attack
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

  def attack_start(source_guid, target_guid) when is_integer(source_guid) and is_integer(target_guid) do
    %__MODULE__{type: :attack_start, source_guid: source_guid, target_guid: target_guid}
  end

  def attack_not_in_range do
    %__MODULE__{type: :attack_not_in_range}
  end

  def attacker_state_update(source_guid, target_guid, damage, attack \\ %{})
      when is_integer(source_guid) and is_integer(target_guid) do
    %__MODULE__{
      type: :attacker_state_update,
      source_guid: source_guid,
      target_guid: target_guid,
      damage: damage,
      attack: attack
    }
  end

  def enqueue(entity, events) when is_list(events) do
    Enum.reduce(events, entity, &enqueue(&2, &1))
  end

  def enqueue(%{internal: %{events: events} = internal} = entity, %__MODULE__{} = event) when is_list(events) do
    %{entity | internal: %{internal | events: events ++ [event]}}
  end

  def enqueue(%{internal: internal} = entity, %__MODULE__{} = event) do
    %{entity | internal: %{internal | events: [event]}}
  end

  def enqueue(entity, _event), do: entity

  def trigger_spell(source_guid, source_level, target_guid, spell_id)
      when is_integer(target_guid) and is_integer(spell_id) do
    %__MODULE__{
      type: :trigger_spell,
      source_guid: source_guid,
      source_level: source_level,
      target_guid: target_guid,
      spell_id: spell_id
    }
  end

  def drain(%{internal: %{events: events} = internal} = entity) when is_list(events) do
    {%{entity | internal: %{internal | events: []}}, events}
  end

  def drain(entity), do: {entity, []}
end
