defmodule ThistleTea.Game.Entity.Logic.Aura.SingleTarget do
  @moduledoc """
  Classifies caster-limited auras and projects accepted holder transitions.
  Recipient-owned generations keep delayed removal requests from cancelling
  a newer cast, including casts applied within the same millisecond.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Aura.SingleTargetClaim
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  def assign(%{internal: %Internal{} = internal} = entity, %Holder{} = holder) do
    if limited?(holder) do
      generation = internal.single_target_sequence + 1
      entity = %{entity | internal: %{internal | single_target_sequence: generation}}
      {entity, %{holder | single_target_generation: generation}}
    else
      {entity, holder}
    end
  end

  def assign(entity, holder), do: {entity, holder}

  def events(previous, current, target_guid) do
    before = claims(previous, target_guid)
    after_claims = claims(current, target_guid)
    if before == after_claims, do: [], else: [%Effects.SingleTargetAurasChanged{claims: after_claims}]
  end

  def claims(holders, target_guid) when is_list(holders) do
    for %Holder{spell: %Spell{} = spell, single_target_generation: generation} = holder <- holders,
        limited?(holder),
        is_integer(generation) do
      %SingleTargetClaim{
        caster_guid: holder.caster_guid,
        target_guid: target_guid,
        holder_key: Holder.key(holder),
        generation: generation,
        spell_family: spell.spell_family,
        spell_icon: spell.spell_icon,
        category: spell.exclusive_category,
        stalked?: Holder.has_aura_type?(holder, :mod_stalked)
      }
    end
  end

  def claims(_holders, _target_guid), do: []

  def conflicts?(%SingleTargetClaim{} = first, %SingleTargetClaim{} = second) do
    first.caster_guid == second.caster_guid and first.target_guid != second.target_guid and
      (same_family_icon?(first, second) or same_category?(first, second))
  end

  def remove(%{unit: %Unit{auras: holders}} = entity, %SingleTargetClaim{} = claim, now, cause \\ :removed) do
    desired =
      Enum.reject(holders || [], fn holder ->
        Holder.key(holder) == claim.holder_key and holder.single_target_generation == claim.generation
      end)

    Transition.run(entity, %Change{holders: desired, cause: cause, now: now})
  end

  def detach(entity, now, opts \\ [])

  def detach(%{object: %{guid: guid}, unit: %Unit{auras: holders}} = entity, now, opts) do
    keep_self? = Keyword.get(opts, :keep_self?, true)
    desired = Enum.reject(holders || [], &(limited?(&1) and (not keep_self? or &1.caster_guid != guid)))
    {entity, events} = Transition.run(entity, %Change{holders: desired, cause: :removed, now: now})

    Effects.enqueue(
      entity,
      events ++
        [%Effects.SingleTargetAurasLeft{}, %Effects.SingleTargetAurasChanged{claims: claims(entity.unit.auras, guid)}]
    )
  end

  def detach(entity, _now, _opts), do: entity

  defp limited?(%Holder{spell: spell}), do: Spell.custom?(spell, :single_target_aura)

  defp same_family_icon?(first, second),
    do: first.spell_family == second.spell_family and first.spell_icon == second.spell_icon

  defp same_category?(first, second),
    do: first.category in [:paladin_judgement, :mage_polymorph] and first.category == second.category
end
