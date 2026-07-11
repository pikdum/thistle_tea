defmodule ThistleTea.Game.Entity.Logic.Aura.Lifecycle do
  @moduledoc """
  Removes auras from an entity for every reason they can end — expired
  duration, interrupt flags (moving, turning, standing), explicit removal or
  player cancel, dispel, and breaking on damage — then resyncs the unit and
  movement state.
  """
  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.MovementSync
  alias ThistleTea.Game.Entity.Logic.Aura.StealthSync
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  @aura_interrupt_damage 0x02
  @aura_interrupt_cast 0x01
  @aura_interrupt_move 0x08
  @aura_interrupt_turning 0x10
  @aura_interrupt_not_seated 0x40000

  def interrupt_mask(:move), do: @aura_interrupt_move ||| @aura_interrupt_turning ||| @aura_interrupt_not_seated
  def interrupt_mask(:cast), do: @aura_interrupt_cast
  def interrupt_mask(:turn), do: @aura_interrupt_turning
  def interrupt_mask(:stand), do: @aura_interrupt_not_seated

  def self_duration_events(%Character{unit: %Unit{auras: holders}}, now) when is_list(holders) and is_integer(now) do
    Enum.flat_map(holders, &duration_event(&1, now))
  end

  def self_duration_events(_entity, _now), do: []

  def expire_due(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) do
    {kept, expired} = Enum.split_with(holders, &Holder.alive?(&1, now))

    if expired == [] do
      {entity, []}
    else
      remove_and_sync(entity, kept, now)
    end
  end

  def expire_due(entity, _now), do: {entity, []}

  def remove_with_interrupt_flags(%{unit: %Unit{auras: holders}} = entity, mask, now)
      when is_list(holders) and holders != [] and is_integer(mask) do
    {removed, kept} = Enum.split_with(holders, &Holder.interruptible?(&1, mask))

    if removed == [] do
      {entity, []}
    else
      remove_and_sync(entity, kept, now)
    end
  end

  def remove_with_interrupt_flags(entity, _mask, _now), do: {entity, []}

  def remove_spells(%{unit: %Unit{auras: holders}} = entity, spell_ids, now)
      when is_list(holders) and holders != [] and is_list(spell_ids) do
    {removed, kept} = Enum.split_with(holders, fn %Holder{spell: %Spell{id: id}} -> id in spell_ids end)

    if removed == [] do
      {entity, []}
    else
      remove_and_sync(entity, kept, now)
    end
  end

  def remove_spells(entity, _spell_ids, _now), do: {entity, []}

  def cancel_spell(%{unit: %Unit{auras: holders}} = entity, spell_id, now)
      when is_list(holders) and holders != [] and is_integer(spell_id) do
    holder = Enum.find(holders, fn %Holder{spell: %Spell{id: id}} -> id == spell_id end)

    if cancelable?(holder) do
      spell_ids = if stealth_holder?(holder), do: stealth_spell_ids(holders), else: [spell_id]
      remove_spells(entity, spell_ids, now)
    else
      {entity, []}
    end
  end

  def cancel_spell(entity, _spell_id, _now), do: {entity, []}

  def dispel(entity, dispel_type, now, polarity \\ nil)

  def dispel(%{unit: %Unit{auras: holders}} = entity, dispel_type, now, polarity)
      when is_list(holders) and holders != [] and is_integer(dispel_type) do
    case dispel_index(holders, dispel_type, polarity) do
      nil ->
        {entity, []}

      index ->
        remove_and_sync(entity, List.delete_at(holders, index), now)
    end
  end

  def dispel(entity, _dispel_type, _now, _polarity), do: {entity, []}

  def break_on_damage(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) and holders != [] do
    {removed, kept} =
      Enum.split_with(holders, fn holder ->
        Holder.has_aura_type?(holder, :mod_confuse) or Holder.interruptible?(holder, @aura_interrupt_damage)
      end)

    if removed == [] do
      entity
    else
      {entity, events} = remove_and_sync(entity, kept, now)
      Event.enqueue(entity, events)
    end
  end

  def break_on_damage(entity, _now), do: entity

  defp remove_and_sync(entity, kept, now) do
    unit = UnitSync.sync_unit(%{entity.unit | auras: kept})

    {entity, events} =
      %{entity | unit: unit}
      |> StealthSync.sync()
      |> MovementSync.sync_movement_state(now)

    {Core.mark_broadcast_update(entity), events}
  end

  defp cancelable?(%Holder{negative?: true}), do: false

  defp cancelable?(%Holder{spell: %Spell{} = spell}) do
    not Spell.attribute?(spell, :passive) and not Spell.attribute?(spell, :cant_cancel)
  end

  defp cancelable?(_holder), do: false

  defp stealth_holder?(%Holder{} = holder) do
    Holder.has_aura_type?(holder, :mod_stealth) or
      Enum.any?(holder.auras, &match?(%Aura{type: :mod_shapeshift, misc_value: 30}, &1))
  end

  defp stealth_holder?(_holder), do: false

  defp stealth_spell_ids(holders) do
    for %Holder{spell: %Spell{id: id}} = holder <- holders, stealth_holder?(holder), do: id
  end

  defp dispel_index(holders, dispel_type, polarity) do
    matches_type? = fn %Holder{spell: %Spell{dispel_type: dt}} -> dt == dispel_type end

    case polarity do
      :negative -> Enum.find_index(holders, &(matches_type?.(&1) and &1.negative?))
      :positive -> Enum.find_index(holders, &(matches_type?.(&1) and not &1.negative?))
      _ -> Enum.find_index(holders, matches_type?)
    end
  end

  def duration_event(%Holder{slot: slot, expires_at: expires_at}, now)
      when is_integer(slot) and is_integer(expires_at) and expires_at != -1 do
    [Event.aura_duration(slot, max(expires_at - now, 0))]
  end

  def duration_event(_holder, _now), do: []
end
