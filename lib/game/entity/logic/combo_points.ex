defmodule ThistleTea.Game.Entity.Logic.ComboPoints do
  @moduledoc """
  Target-bound combo points and temporary builder points. Any subsequent
  builder makes retained points permanent; only natural aura expiry subtracts
  them. Awards return to the caster owner after the target resolves the hit.
  """

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def add(entity, target_guid, amount, now \\ 0)

  def add(%Character{} = entity, target_guid, amount, now)
      when is_integer(target_guid) and target_guid > 0 and is_integer(amount) and amount > 0 do
    entity = remove_retention(entity, now)
    current = if entity.internal.combo_target_guid == target_guid, do: entity.player.combo_points || 0, else: 0
    put_points(entity, target_guid, min(current + amount, 5))
  end

  def add(entity, _target_guid, _amount, _now), do: entity

  def consume(entity, now \\ 0)

  def consume(%Character{} = entity, now) do
    entity = remove_retention(entity, now)

    if (entity.player.combo_points || 0) > 0 or entity.internal.combo_target_guid != nil do
      put_points(entity, nil, 0)
    else
      entity
    end
  end

  def consume(entity, _now), do: entity

  def award(%Character{unit: %{health: health}} = entity, %Effects.AddComboPoints{} = award, now)
      when health > 0 and award.source_guid == entity.object.guid and award.amount > 0 do
    if Death.alive?(entity), do: apply_award(entity, award, now), else: entity
  end

  def award(entity, _award, _now), do: entity

  defp apply_award(entity, award, now) do
    entity = add(entity, award.target_guid, award.amount, now)

    case award.retention do
      {%Spell{} = spell, context} ->
        context = %{context | target_guid: entity.object.guid, target_role: :caster}
        {entity, events} = Aura.apply_spell(entity, context, spell, now)
        Effects.enqueue(entity, events)

      nil ->
        entity
    end
  end

  def retention_spell(%Spell{effects: effects} = spell) do
    retained = Enum.filter(effects, &retention_effect?/1)

    if retained != [] and Enum.any?(effects, &(&1.type == :add_combo_points)) do
      %{spell | effects: retained}
    end
  end

  def retention_effect?(%Effect{type: :apply_aura, aura: :retain_combo_points}), do: true
  def retention_effect?(_effect), do: false

  def expire(%Character{} = entity, removed, :expired) do
    amount =
      for %Holder{auras: auras} <- removed,
          %AuraData{type: :retain_combo_points, amount: amount} <- auras,
          reduce: 0 do
        total -> total + max(amount, 0)
      end

    if amount > 0 and is_integer(entity.internal.combo_target_guid) do
      put_points(entity, entity.internal.combo_target_guid, max((entity.player.combo_points || 0) - amount, 0))
    else
      entity
    end
  end

  def expire(entity, _removed, _cause), do: entity

  defp remove_retention(entity, now) do
    {entity, events} = Aura.remove_aura_types(entity, [:retain_combo_points], now)
    Effects.enqueue(entity, events)
  end

  defp put_points(entity, target_guid, points) do
    %{
      entity
      | player: %{
          entity.player
          | field_combo_target: target_guid || entity.player.field_combo_target,
            combo_points: points
        },
        internal: %{entity.internal | combo_target_guid: target_guid, combo_expires_at: nil}
    }
    |> Core.mark_broadcast_update()
  end
end
