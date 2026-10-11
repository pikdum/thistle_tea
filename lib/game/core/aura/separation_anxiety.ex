defmodule ThistleTea.Game.Core.Aura.SeparationAnxiety do
  @moduledoc "Five-second boss-distance checks empower separated Molten Core adds."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect

  @buffs %{21_094 => 21_095, 23_487 => 23_492}

  def spell?(%Spell{id: id}), do: is_map_key(@buffs, id)
  def spell?(_spell), do: false

  def interval(%Spell{} = spell, %Effect{aura: :dummy}), do: if(spell?(spell), do: 5_000)
  def interval(%Spell{}, %Effect{}), do: nil

  def tick_events(
        %{object: %{guid: guid}, unit: %Unit{health: health, level: level}} = entity,
        %Holder{spell: %Spell{id: id}} = holder,
        %Aura{index: index}
      )
      when is_map_key(@buffs, id) and is_integer(health) and health > 0 do
    if separated?(entity, holder.cast_context, effect_radius(holder.spell, index)) do
      [Effects.trigger_spell(guid, level || 1, guid, @buffs[id], triggered_by_spell_id: id)]
    else
      []
    end
  end

  def tick_events(_entity, _holder, _aura), do: []

  defp separated?(
         %{internal: %{world: world}, movement_block: %{position: {x, y, z, _}}, unit: %Unit{} = unit},
         %CastContext{caster_available?: true, caster_position: {world, cx, cy, cz}} = context,
         radius
       )
       when is_number(radius) and radius > 0 do
    maximum = radius + bounding_radius(unit.bounding_radius) + bounding_radius(context.caster_bounding_radius)
    Math.distance({x, y, z}, {cx, cy, cz}) >= maximum
  end

  defp separated?(_entity, _context, _radius), do: false

  defp effect_radius(%Spell{effects: effects}, index) do
    case Enum.find(effects, &(&1.index == index)) do
      %Effect{radius_yards: radius} -> radius
      _missing -> nil
    end
  end

  defp bounding_radius(radius) when is_number(radius), do: max(radius, 0.0)
  defp bounding_radius(_radius), do: 0.0
end
