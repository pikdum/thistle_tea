defmodule ThistleTea.Game.Entity.SpellReception do
  @moduledoc """
  Supplies current world projections to incoming spell logic at the target's
  owning boundary. Dispel resistance belongs to each aura's original caster.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.DispelResistance
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Metadata

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) do
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
    %{dispel_resistance: DispelResistance.projection(target)}
  end

  defp metadata(_target, guid), do: Metadata.get(guid)
end
