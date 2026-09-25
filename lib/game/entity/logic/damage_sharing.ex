defmodule ThistleTea.Game.Entity.Logic.DamageSharing do
  @moduledoc """
  Allocates post-absorption damage to available aura casters, applying flat
  shares before percentage shares. Transfers retain their aura and original
  attacker and cannot produce another transfer.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Spell

  @types [:split_damage_flat, :split_damage_percent]

  def casters(%{object: %{guid: guid}, unit: %Unit{auras: holders}}) do
    for %Holder{caster_guid: caster} = holder <- holders || [],
        is_integer(caster) and caster > 0 and caster != guid,
        Holder.has_any_type?(holder, @types),
        uniq: true,
        do: caster
  end

  def casters(_entity), do: []

  def split(entity, damage, school, now, opts) do
    available = Keyword.get(opts, :damage_sharing_targets, MapSet.new())

    entity
    |> shares(school, now, available)
    |> Enum.reduce({damage, []}, fn {holder, aura}, {remaining, transfers} ->
      amount = shared_amount(remaining, holder, aura)

      if amount > 0 do
        transfer = %Effects.SharedDamage{
          target_guid: holder.caster_guid,
          source_guid: Keyword.get(opts, :source),
          source_owner_guid: Keyword.get(opts, :source_owner),
          source_level: Keyword.get(opts, :source_level) || 1,
          reflected_by_guid: Keyword.get(opts, :reflected_by),
          world: entity.internal.world,
          spell: holder.spell,
          damage_spell: Keyword.get(opts, :spell),
          school: school,
          damage: amount,
          kind: aura.type,
          periodic?: Keyword.get(opts, :periodic, false),
          resistance_penetration: Keyword.get(opts, :resistance_penetration, [])
        }

        {remaining - amount, transfers ++ [transfer]}
      else
        {remaining, transfers}
      end
    end)
  end

  def receive(entity, %Effects.SharedDamage{} = transfer, now, opts \\ []) do
    if Death.alive?(entity) do
      {entity, damage, absorbed, resisted} = receive_damage(entity, transfer, now, opts)

      event =
        Effects.spell_damage(transfer.source_guid, entity.object.guid, transfer.spell, damage,
          absorbed: absorbed,
          resisted: resisted,
          periodic?: transfer.periodic?,
          proc_type: nil
        )

      Effects.enqueue(entity, %{event | school: transfer.school})
    else
      entity
    end
  end

  defp receive_damage(entity, transfer, now, opts) do
    if protected?(entity) do
      {entity, transfer.damage, transfer.damage, 0}
    else
      absorb? = absorb_transfer?(entity, transfer)
      resisted = if absorb?, do: resisted_amount(entity, transfer, opts), else: 0

      {entity, damage, absorbed} =
        Core.take_damage_with_mitigation(entity, transfer.damage - resisted, now,
          shared_damage: if(absorb?, do: :absorb, else: :unmitigated),
          school: transfer.school,
          spell: transfer.damage_spell,
          source: transfer.source_guid,
          source_owner: transfer.source_owner_guid,
          reflected_by: transfer.reflected_by_guid,
          death_durability_loss?: false,
          periodic: true
        )

      {entity, damage, absorbed, resisted}
    end
  end

  defp protected?(%{internal: %Internal{taxi_flight: flight}}) when not is_nil(flight), do: true

  defp protected?(%Mob{internal: %Internal{blackboard: %{navigation: %{returning_home?: true}}}}), do: true

  defp protected?(_entity), do: false

  defp shares(%{object: %{guid: guid}, unit: %Unit{auras: holders}}, school, now, available) do
    for type <- @types,
        %Holder{} = holder <- holders || [],
        holder.caster_guid != guid and MapSet.member?(available, holder.caster_guid) and Holder.alive?(holder, now),
        %Aura{type: ^type, misc_value: mask} = aura <- holder.auras,
        is_integer(mask) and Bitwise.band(mask, Spell.school_mask(school)) != 0,
        do: {holder, aura}
  end

  defp shares(_entity, _school, _now, _available), do: []

  defp shared_amount(damage, holder, %Aura{type: type, amount: amount}) when is_number(amount) and amount > 0 do
    amount = amount * max(holder.stacks || 1, 1)
    amount = if type == :split_damage_percent, do: damage * amount / 100, else: amount
    min(max(trunc(amount), 0), damage)
  end

  defp shared_amount(_damage, _holder, _aura), do: 0

  defp absorb_transfer?(entity, %Effects.SharedDamage{kind: :split_damage_flat}),
    do: not AuraLogic.has_aura?(entity, :split_damage_flat)

  defp absorb_transfer?(_entity, _transfer), do: false

  defp resisted_amount(_entity, %Effects.SharedDamage{school: :physical}, _opts), do: 0

  defp resisted_amount(entity, %Effects.SharedDamage{} = transfer, opts) do
    resistance =
      entity
      |> SpellResist.school_resistances()
      |> Map.fetch!(Spell.school_index(transfer.school))
      |> ResistancePenetration.resistance(transfer.resistance_penetration, transfer.school)

    SpellResist.resisted_amount(
      transfer.damage,
      resistance,
      transfer.source_level,
      [
        spell: transfer.damage_spell,
        dot?: true,
        target_creature?: not is_struct(entity, Character),
        level_diff: (entity.unit.level || 1) - transfer.source_level
      ] ++ Keyword.take(opts, [:roll])
    )
  end
end
