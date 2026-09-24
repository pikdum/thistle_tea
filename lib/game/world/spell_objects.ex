defmodule ThistleTea.Game.World.SpellObjects do
  @moduledoc "Resolves per-effect object targets from live presence and preloaded spell selectors."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.ObjectTargets
  alias ThistleTea.Game.Spell.ObjectTargets.Selector
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetLimit
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.ScriptedEvent

  def resolve(caster, %Spell{} = spell, %Target{} = targets, focus \\ nil) do
    spell.effects
    |> Enum.filter(&(&1.type == :activate_object))
    |> Enum.reduce_while(%ObjectTargets{}, fn effect, snapshot ->
      case effect_targets(caster, spell, effect, targets, focus) do
        {:ok, guids} ->
          selected = TargetLimit.select(guids, spell)
          {:cont, %{snapshot | by_effect: Map.put(snapshot.by_effect, effect.index, selected)}}

        {:error, reason} ->
          {:halt, %{snapshot | error: reason}}
      end
    end)
  end

  defp effect_targets(caster, spell, effect, targets, focus) do
    modes = [effect.implicit_target_a, effect.implicit_target_b]

    cond do
      :game_object in modes ->
        explicit(caster, spell, targets)

      :game_object_near_caster in modes ->
        nearest(caster, spell, effect, focus)

      :game_objects_at_source in modes ->
        area(caster, spell, effect, targets.source_location || position(caster))

      :game_objects_at_destination in modes ->
        area(caster, spell, effect, targets.destination_location || position(caster))

      true ->
        {:error, :bad_targets}
    end
  end

  defp explicit(caster, spell, targets) do
    guid = Target.object_guid(targets)
    world = caster.internal.world

    with true <- is_integer(guid) and Guid.entity_type(guid) == :game_object,
         %{go_spawned?: true} <- Metadata.get(guid),
         {^world, x, y, z} <- World.position(guid),
         true <- is_pid(Entity.pid(guid)),
         true <- Math.distance(position(caster), {x, y, z}) <= (spell.range_yards || 0),
         true <-
           Spell.attribute?(spell, :ignore_line_of_sight) or
             Pathfinding.line_of_sight?(world, position(caster), {x, y, z}) do
      {:ok, [guid]}
    else
      _ -> {:error, :bad_targets}
    end
  end

  defp nearest(_caster, %Spell{object_targets: []}, _effect, _focus), do: {:error, :bad_targets}

  defp nearest(caster, spell, effect, focus) do
    selectors = selectors(spell, effect)
    range = Focus.range(radius(spell, effect), caster_radius(caster))

    guids =
      caster
      |> candidates(position(caster), range)
      |> Enum.filter(fn {guid, _distance} -> Enum.any?(selectors, &matches?(caster, guid, &1, focus)) end)
      |> Enum.take(1)
      |> Enum.map(&elem(&1, 0))

    if guids == [] and spell.id in [15_958, 16_447, 24_973], do: {:error, :bad_targets}, else: {:ok, guids}
  end

  defp area(caster, spell, effect, origin) do
    entries = spell |> selectors(effect) |> MapSet.new(& &1.entry)

    guids =
      caster
      |> candidates(origin, Focus.range(radius(spell, effect), 0))
      |> Enum.filter(fn {guid, _distance} -> MapSet.member?(entries, Guid.entry(guid)) end)
      |> Enum.map(&elem(&1, 0))

    {:ok, guids}
  end

  defp selectors(%Spell{object_targets: selectors}, %Effect{index: index}),
    do: Enum.filter(selectors, &((&1.inverse_effect_mask &&& 1 <<< index) == 0))

  defp candidates(caster, origin, radius) do
    world = caster.internal.world

    object_candidates(world, origin, radius)
    |> Enum.flat_map(fn guid ->
      with %{go_spawned?: true} <- Metadata.get(guid),
           {^world, x, y, z} <- World.position(guid),
           true <- is_pid(Entity.pid(guid)),
           distance when distance <= radius <- Math.distance(origin, {x, y, z}) do
        [{guid, distance}]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(fn {guid, distance} -> {distance, guid} end)
  end

  defp object_candidates(world, _origin, radius) when radius > 200, do: World.game_objects_in(world)
  defp object_candidates(world, origin, radius), do: World.nearby_candidates(:game_objects, world, origin, radius)

  defp matches?(_caster, guid, %Selector{entry: 0}, %{guid: guid}), do: true
  defp matches?(_caster, _guid, %Selector{entry: 0}, _focus), do: false

  defp matches?(caster, guid, %Selector{entry: entry, condition: condition}, _focus) do
    Guid.entry(guid) == entry and condition_met?(caster, guid, condition)
  end

  defp condition_met?(_caster, _guid, nil), do: true

  defp condition_met?(caster, guid, condition) do
    results = ScriptedEvent.condition_results(caster.internal.world, caster.object.guid, guid, [condition])
    Map.get(results, condition.entry) == :met
  end

  defp radius(_spell, %Effect{radius_yards: radius}) when is_number(radius) and radius > 0, do: radius
  defp radius(spell, _effect), do: spell.range_yards || 0

  defp position(%{movement_block: %{position: {x, y, z, _}}}), do: {x, y, z}

  defp caster_radius(%{unit: %{bounding_radius: radius}}), do: radius
  defp caster_radius(_caster), do: nil
end
