defmodule ThistleTea.Game.World.Spell.SpellRequirements do
  @moduledoc "Resolves nearby cast requirements from live presence and cached metadata."

  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastTarget
  alias ThistleTea.Game.Core.Spell.CorpseTarget
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.Requirements
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Reaction
  alias ThistleTea.Game.World.Spell.SpellAreas
  alias ThistleTea.Game.World.Spell.SpellEnvironment
  alias ThistleTea.Game.World.Spell.SpellFocus
  alias ThistleTea.Game.World.Spell.SpellLocations
  alias ThistleTea.Game.World.Spell.SpellMounts
  alias ThistleTea.Game.World.Spell.SpellObjects
  alias ThistleTea.Game.World.Spell.SpellTargetInfo
  alias ThistleTea.Game.World.Spell.SpellUnits
  alias ThistleTea.Game.World.Visibility

  def resolve(caster, %Spell{} = spell, targets \\ Target.none(), opts \\ []) do
    requirements = resolve_targets(caster, spell, targets)

    targets =
      targets
      |> LocationTargets.apply(requirements.locations)
      |> UnitTargets.item_selection(requirements.units, Keyword.get(opts, :cast_item_guid))

    %{
      requirements
      | corpse: corpse(caster, spell),
        aura_target: aura_target(caster, targets),
        cast_target: %CastTarget{
          targets: targets,
          info: SpellTargetInfo.resolve(caster, spell, targets),
          destination_los?: World.line_of_sight?(caster, targets.destination_location)
        },
        spell_area: SpellAreas.context(caster, spell),
        outdoors?: SpellEnvironment.context(caster, spell),
        mount_context: SpellMounts.context(caster, spell)
    }
  end

  def resolve_targets(caster, %Spell{} = spell, %Target{} = targets) do
    focus = SpellFocus.find(caster, spell)
    locations = SpellLocations.resolve(caster, spell, targets, focus)
    targets = LocationTargets.apply(targets, locations)
    objects = SpellObjects.resolve(caster, spell, targets, focus, locations)

    %Requirements{
      focus: focus,
      locations: locations,
      objects: LocationTargets.put_objects(objects, spell, locations),
      units: SpellUnits.resolve(caster, spell, targets)
    }
  end

  defp aura_target(caster, targets) do
    guid = Target.unit_guid(targets)
    if is_integer(guid) and guid != caster.object.guid, do: Metadata.query(guid, [:level])
  end

  def corpse(caster, %Spell{} = spell) do
    if CorpseTarget.required?(spell), do: find_corpse(caster, spell.range_yards || 0)
  end

  defp find_corpse(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _}}} = caster, range) do
    [:mobs, :players, :corpses]
    |> Enum.flat_map(&World.nearby_candidates(&1, world, {x, y, z}, range))
    |> Enum.flat_map(fn guid ->
      case candidate(caster, guid, range) do
        nil -> []
        corpse -> [corpse]
      end
    end)
    |> Enum.min_by(
      fn %CorpseTarget{guid: guid, position: {_, tx, ty, tz}} ->
        {Math.distance({x, y, z}, {tx, ty, tz}), guid}
      end,
      fn -> nil end
    )
  end

  defp candidate(caster, guid, range) do
    kind = Guid.entity_type(guid)

    with %{} = metadata <- Metadata.get(guid),
         {world, x, y, z} = position <- World.position(guid),
         true <- world == caster.internal.world,
         true <- within_range?(caster, {x, y, z}, range, metadata) do
      metadata =
        metadata
        |> Map.put(:friendly?, Reaction.friendly?(caster, reaction_target(guid, metadata)))
        |> Map.put(:visible?, Visibility.can_see?(%{guid: caster.object.guid, character: caster}, guid))

      if CorpseTarget.eligible?(kind, metadata), do: %CorpseTarget{guid: guid, kind: kind, position: position}
    else
      _missing -> nil
    end
  end

  defp reaction_target(_guid, %{owner: owner} = corpse) when is_integer(owner),
    do: owner |> Reaction.actor() |> Map.merge(Map.take(corpse, [:faction_template, :faction_can_have_reputation?]))

  defp reaction_target(guid, metadata), do: Map.put(metadata, :guid, guid)

  defp within_range?(%{unit: unit, movement_block: %{position: {x, y, z, _}}}, position, range, metadata),
    do:
      Math.distance({x, y, z}, position) <
        CorpseTarget.range(range, unit.bounding_radius, Map.get(metadata, :bounding_radius))
end
