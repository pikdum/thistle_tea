defmodule ThistleTea.Game.Entity.SpellReception do
  @moduledoc """
  Supplies current world projections to incoming spell logic at the target's
  owning boundary. Dispel resistance and threat modifiers belong to each
  spell's original caster; periodic threat is refreshed for every due tick.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.DispelResistance
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.HealingReceived
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.SpellThreat, as: SpellThreatLoader
  alias ThistleTea.Game.World.Metadata

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) do
    context = threat_context(target, context, spell)

    context =
      if Enum.any?(spell.effects, &(&1.type == :dispel)) do
        %{context | dispel_resistance: resistance(target)}
      else
        context
      end

    SpellEffect.receive(target, context, spell, now)
  end

  def receive(target, caster_guid, %Spell{} = spell, now) when is_integer(caster_guid) do
    receive(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell, now)
  end

  def aura_contexts(%{unit: %{auras: holders}} = target, now) when is_list(holders) do
    for %Holder{} = holder <- holders,
        Enum.any?(holder.auras, &(is_integer(&1.next_tick_at) and &1.next_tick_at <= now)),
        into: %{} do
      context =
        holder.cast_context ||
          %CastContext{
            caster_guid: holder.caster_guid,
            caster_owner_guid: holder.caster_owner_guid,
            reflected_by_guid: holder.reflected_by_guid,
            caster_level: holder.caster_level,
            spell: holder.spell
          }

      {{holder.spell.id, holder.caster_guid, holder.item_source}, threat_context(target, context, holder.spell)}
    end
  end

  def aura_contexts(_target, _now), do: %{}

  def heal(target, %Effects.HealEntity{spell: %Spell{} = spell, amount: amount} = effect) do
    if Core.dead?(target) do
      target
    else
      context = threat_context(target, %CastContext{caster_guid: effect.source_guid}, spell)
      healing = HealingReceived.amount(target, amount)
      events = SpellThreat.heal_events(target, context, spell, healing, periodic?: true)
      target |> Core.heal(healing) |> Effects.enqueue(events)
    end
  end

  def heal(target, %Effects.HealEntity{amount: amount}), do: HealingReceived.heal(target, amount)
  def heal(target, amount) when is_number(amount), do: HealingReceived.heal(target, amount)

  defp threat_context(target, %CastContext{} = context, spell) do
    context = %{context | spell_threat: SpellThreatLoader.get(spell.id) || context.spell_threat}

    case metadata(target, context.caster_guid) do
      %{spell_threat: %SpellThreat{} = projection} -> SpellThreat.put_context(context, spell, projection)
      _missing -> context
    end
  end

  defp resistance(target) do
    Map.new(target.unit.auras || [], fn %Holder{} = holder ->
      projection = caster_projection(target, holder)
      {{holder.spell.id, holder.caster_guid}, DispelResistance.chance(projection, holder.spell)}
    end)
  end

  defp caster_projection(target, %Holder{caster_guid: caster, caster_owner_guid: owner}) do
    case metadata(target, caster) do
      nil -> []
      caster_metadata when owner in [nil, caster] -> Map.get(caster_metadata, :dispel_resistance, [])
      _caster_metadata -> Map.get(metadata(target, owner) || %{}, :dispel_resistance, [])
    end
  end

  defp metadata(%{object: %{guid: guid}} = target, guid) do
    %{dispel_resistance: DispelResistance.projection(target), spell_threat: SpellThreat.projection(target)}
  end

  defp metadata(_target, guid), do: Metadata.get(guid)
end
