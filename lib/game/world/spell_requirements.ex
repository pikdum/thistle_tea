defmodule ThistleTea.Game.World.SpellRequirements do
  @moduledoc "Resolves nearby cast requirements from live presence and cached metadata."

  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Requirements
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpellFocus
  alias ThistleTea.Game.World.Visibility

  def resolve(caster, %Spell{} = spell) do
    %Requirements{focus: SpellFocus.find(caster, spell), corpse: corpse(caster, spell)}
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
      reaction_target = Map.put(metadata, :guid, Map.get(metadata, :owner, guid))

      metadata =
        metadata
        |> Map.put(:friendly?, Hostility.friendly?(caster, reaction_target))
        |> Map.put(:visible?, Visibility.can_see?(%{guid: caster.object.guid, character: caster}, guid))

      if CorpseTarget.eligible?(kind, metadata), do: %CorpseTarget{guid: guid, kind: kind, position: position}
    else
      _missing -> nil
    end
  end

  defp within_range?(%{unit: unit, movement_block: %{position: {x, y, z, _}}}, position, range, metadata),
    do:
      Math.distance({x, y, z}, position) <
        CorpseTarget.range(range, unit.bounding_radius, Map.get(metadata, :bounding_radius))
end
