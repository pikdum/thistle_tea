defmodule ThistleTea.Game.World.SpellUnits do
  @moduledoc "Selects nearby creatures from cached entry, life-state, and condition requirements."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.EntityContext
  alias ThistleTea.Game.Entity.Logic.Condition.Requirements
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Radius
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.UnitTargets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.ScriptedEvent

  def resolve(caster, %Spell{} = spell, %Target{} = targets) do
    spell.effects
    |> Enum.filter(&UnitTargets.scripted?/1)
    |> Enum.reduce_while(%UnitTargets{}, fn effect, snapshot ->
      case nearest(caster, spell, effect, targets) do
        nil -> {:halt, %{snapshot | error: :bad_targets}}
        guid -> {:cont, %{snapshot | by_effect: Map.put(snapshot.by_effect, effect.index, [guid])}}
      end
    end)
  end

  defp nearest(caster, spell, effect, targets) do
    selectors = UnitTargets.selectors(spell, effect)
    radius = Radius.effect(effect, Modifiers.snapshot(caster, spell), spell.range_yards || 0)
    selected = Target.unit_guid(targets)

    candidates(caster, radius)
    |> Enum.flat_map(fn guid ->
      case candidate(caster, guid, radius, selectors) do
        nil -> []
        distance -> [{guid != selected or distance > radius, distance, guid}]
      end
    end)
    |> Enum.min(fn -> nil end)
    |> case do
      nil -> nil
      {_unselected, _distance, guid} -> guid
    end
  end

  defp candidates(caster, radius) when radius > 200 do
    World.mobs_in(caster.internal.world)
  end

  defp candidates(caster, radius),
    do:
      World.nearby_candidates(:mobs, caster.internal.world, position(caster), radius + reach(caster.unit.combat_reach))

  defp candidate(caster, guid, radius, selectors) do
    world = caster.internal.world

    with %{} = metadata <- Metadata.get(guid),
         {^world, x, y, z} <- World.position(guid),
         true <- is_pid(Entity.pid(guid)),
         distance = Math.distance(position(caster), {x, y, z}),
         true <- distance <= radius + reach(caster.unit.combat_reach) + reach(Map.get(metadata, :combat_reach)),
         true <- Enum.any?(selectors, &matches?(caster, guid, metadata, &1)) do
      max(distance - reach(caster.unit.bounding_radius) - reach(Map.get(metadata, :bounding_radius)), 0)
    else
      _ -> nil
    end
  end

  defp matches?(caster, guid, metadata, selector) do
    Map.get(metadata, :entry, Guid.entry(guid)) == selector.entry and
      Map.get(metadata, :alive?) == selector.alive? and condition_met?(caster, guid, metadata, selector.condition)
  end

  defp condition_met?(_caster, _guid, _metadata, nil), do: true

  defp condition_met?(caster, guid, metadata, condition) do
    conditions = Requirements.environment_conditions(condition)
    results = ScriptedEvent.condition_results(caster.internal.world, caster.object.guid, guid, conditions)

    context =
      Context.new(
        source: EntityContext.subject(caster, Time.now()),
        target: EntityContext.metadata_subject(guid, metadata, position: World.position(guid)),
        world: %{map_id: caster.internal.world.map_id},
        environment: %{condition_results: results}
      )

    Condition.evaluate(context, condition) == :met
  end

  defp reach(value) when is_number(value) and value > 0, do: value
  defp reach(_value), do: 0
  defp position(%{movement_block: %{position: {x, y, z, _}}}), do: {x, y, z}
end
