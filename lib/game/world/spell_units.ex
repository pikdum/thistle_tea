defmodule ThistleTea.Game.World.SpellUnits do
  @moduledoc "Selects nearby creatures from cached entry, life-state, and condition requirements."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.EntityContext
  alias ThistleTea.Game.Entity.Logic.Condition.Requirements
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cone
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Radius
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetLimit
  alias ThistleTea.Game.Spell.UnitTargets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.ScriptedEvent

  def resolve(caster, %Spell{} = spell, %Target{} = targets) do
    spell.effects
    |> Enum.filter(&UnitTargets.scripted?/1)
    |> Enum.reduce_while(%UnitTargets{}, fn effect, snapshot ->
      case effect_targets(caster, spell, effect, targets) do
        {:error, reason} ->
          {:halt, %{snapshot | error: reason}}

        {:ok, guids} ->
          snapshot = retain_effect(snapshot, effect, guids)
          {:cont, snapshot}
      end
    end)
  end

  defp retain_effect(snapshot, effect, guids) do
    selected = if UnitTargets.mode(effect) == :creature_near_caster, do: List.first(guids)

    %{
      snapshot
      | selected_guid: snapshot.selected_guid || selected,
        by_effect: Map.put(snapshot.by_effect, effect.index, guids)
    }
  end

  defp effect_targets(caster, spell, effect, targets) do
    case UnitTargets.mode(effect) do
      :creature_near_caster ->
        case nearest(caster, spell, effect, targets) do
          nil -> {:error, :bad_targets}
          guid -> {:ok, [guid]}
        end

      mode ->
        {:ok, area(caster, spell, effect, targets, mode)}
    end
  end

  defp area(_caster, _spell, %Effect{type: type}, _targets, :script_units_at_destination)
       when type in [:persistent_area_aura, :summon, :summon_wild, :summon_object_wild], do: []

  defp area(caster, spell, effect, targets, mode) do
    origin = area_origin(caster, effect, targets, mode)
    radius = Radius.effect(effect, Modifiers.snapshot(caster, spell), spell.range_yards || 0)
    selectors = UnitTargets.selectors(spell, effect)

    area_candidates(caster, origin, radius)
    |> Enum.uniq()
    |> Enum.flat_map(&area_candidate(caster, &1, origin, radius, mode, spell.cone_degrees))
    |> Enum.filter(fn {guid, metadata, _distance} ->
      area_recipient?(caster, spell, effect, mode, guid, metadata, selectors) and
        line_of_sight?(caster, spell, guid)
    end)
    |> Enum.sort_by(fn {guid, _metadata, distance} -> {distance, guid} end)
    |> Enum.map(&elem(&1, 0))
    |> TargetLimit.select(spell, Target.unit_guid(targets))
  end

  defp area_origin(caster, effect, targets, :script_units_at_source) do
    if :caster_source in [effect.implicit_target_a, effect.implicit_target_b],
      do: position(caster),
      else: targets.source_location || position(caster)
  end

  defp area_origin(caster, effect, targets, :script_units_at_destination) do
    if :caster_destination in [effect.implicit_target_a, effect.implicit_target_b],
      do: position(caster),
      else: targets.destination_location || position(caster)
  end

  defp area_origin(caster, _effect, _targets, :script_units_in_cone), do: position(caster)

  defp area_candidates(caster, _origin, radius) when radius > 200,
    do: [caster.object.guid | World.mobs_in(caster.internal.world) ++ World.players_in(caster.internal.world)]

  defp area_candidates(caster, origin, radius),
    do: [
      caster.object.guid
      | Enum.flat_map([:mobs, :players], &World.nearby_candidates(&1, caster.internal.world, origin, radius))
    ]

  defp area_candidate(caster, guid, origin, radius, mode, cone_degrees) do
    with {position, metadata} <- area_facts(caster, guid),
         true <- mode == :script_units_at_destination or guid != caster.object.guid,
         distance = Math.distance(origin, position),
         true <- distance <= radius + area_reach(guid, metadata),
         true <- area_shape?(mode, cone_degrees, caster.movement_block.position, position) do
      [{guid, metadata, distance}]
    else
      _ -> []
    end
  end

  defp area_shape?(:script_units_in_cone, degrees, caster, target), do: Cone.contains?(degrees, caster, target)
  defp area_shape?(_mode, _degrees, _caster, _target), do: true

  defp area_facts(%{object: %{guid: guid}} = caster, guid) do
    {position(caster),
     %{
       guid: guid,
       entry: caster.object.entry,
       alive?: caster.unit.health > 0,
       combat_reach: caster.unit.combat_reach,
       owner_player_guid: if(Guid.entity_type(guid) == :player, do: guid)
     }}
  end

  defp area_facts(caster, guid) do
    world = caster.internal.world

    with %{} = metadata <- Metadata.get(guid),
         {^world, x, y, z} <- World.position(guid),
         true <- is_pid(Entity.pid(guid)),
         do: {{x, y, z}, Map.put(metadata, :guid, guid)}
  end

  defp area_reach(guid, metadata) do
    if Guid.entity_type(guid) == :player or Map.get(metadata, :owner_player_guid),
      do: 0,
      else: reach(Map.get(metadata, :combat_reach))
  end

  defp area_recipient?(caster, spell, effect, mode, guid, metadata, selectors) do
    cond do
      spell.unit_targets != [] or spell.object_targets != [] ->
        Enum.any?(selectors, &matches?(caster, guid, metadata, &1))

      mode == :script_units_in_cone and effect.type != :script_effect ->
        Hostility.valid_attack_target?(caster, metadata, area?: true) and
          Hostility.can_attack_without_flagging?(caster, metadata)

      mode == :script_units_at_destination ->
        unrestricted_destination_target?(caster, spell, metadata)

      true ->
        true
    end
  end

  defp unrestricted_destination_target?(caster, spell, metadata) do
    (metadata.alive? or Spell.attribute?(spell, :allow_dead_target)) and
      Hostility.targetable_by?(caster, metadata, not Spell.harmful?(spell), area?: true)
  end

  defp line_of_sight?(%{object: %{guid: guid}}, _spell, guid), do: true

  defp line_of_sight?(caster, spell, guid),
    do: Spell.attribute?(spell, :ignore_line_of_sight) or World.line_of_sight?(caster, guid)

  defp nearest(caster, spell, effect, targets) do
    case nearest_candidate(caster, spell, effect, targets) do
      nil -> nil
      {_unselected, _distance, guid} -> guid
    end
  end

  def nearest_candidate(caster, %Spell{} = spell, %Effect{} = effect, %Target{} = targets) do
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
        target: condition_target(caster, guid, metadata),
        world: %{map_id: caster.internal.world.map_id},
        environment: %{condition_results: results}
      )

    Condition.evaluate(context, condition) == :met
  end

  defp condition_target(%{object: %{guid: guid}} = caster, guid, _metadata),
    do: EntityContext.subject(caster, Time.now())

  defp condition_target(_caster, guid, metadata),
    do: EntityContext.metadata_subject(guid, metadata, position: World.position(guid))

  defp reach(value) when is_number(value) and value > 0, do: value
  defp reach(_value), do: 0
  defp position(%{movement_block: %{position: {x, y, z, _}}}), do: {x, y, z}
end
