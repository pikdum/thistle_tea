defmodule ThistleTea.Game.World.SpellLocations do
  @moduledoc "Resolves scripted destinations from nearby creatures, corpses, and game objects."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.LocationTargets
  alias ThistleTea.Game.Spell.LocationTargets.Selection
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpellObjects
  alias ThistleTea.Game.World.SpellUnits

  def resolve(caster, %Spell{} = spell, %Target{} = targets, focus \\ nil) do
    spell.effects
    |> Enum.filter(&LocationTargets.scripted?/1)
    |> Enum.reduce_while(%LocationTargets{}, fn effect, snapshot ->
      case selection(caster, spell, effect, targets, focus) do
        %Selection{} = selected ->
          {:cont, %{snapshot | by_effect: Map.put(snapshot.by_effect, effect.index, selected)}}

        nil ->
          {:halt, %{snapshot | error: :bad_targets}}
      end
    end)
  end

  defp selection(caster, spell, effect, targets, focus) do
    candidates = [
      unit_candidate(caster, spell, effect, targets),
      object_candidate(caster, spell, effect, focus)
    ]

    candidates
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
    |> case do
      {_unselected, _distance, guid, kind} ->
        case World.position(guid) do
          {world, x, y, z} when world == caster.internal.world ->
            %Selection{guid: guid, kind: kind, position: {x, y, z}}

          _ ->
            nil
        end

      nil ->
        nil
    end
  end

  defp unit_candidate(caster, spell, effect, targets) do
    case SpellUnits.nearest_candidate(caster, spell, effect, targets) do
      {unselected, distance, guid} -> {unselected, distance, guid, :unit}
      nil -> nil
    end
  end

  defp object_candidate(caster, spell, effect, focus) do
    case SpellObjects.nearest_candidate(caster, spell, effect, focus) do
      {guid, distance} -> {true, distance, guid, :game_object}
      nil -> nil
    end
  end
end
