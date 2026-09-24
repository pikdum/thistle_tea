defmodule ThistleTea.Game.Entity.ChainTargets do
  @moduledoc """
  Resolves successive spell jumps from live spatial and owner-published observations.
  """

  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Chain
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @jump_radius 10.0

  def expand(caster, spell, initial, opts \\ [])

  def expand(caster, %Spell{} = spell, [first] = initial, opts) do
    jump(caster, spell, first, initial, Chain.count(caster, spell) - 1, opts)
  end

  def expand(_caster, _spell, initial, _opts), do: initial

  defp jump(_caster, _spell, _previous, selected, remaining, _opts) when remaining <= 0, do: selected

  defp jump(caster, spell, previous, selected, remaining, opts) do
    case next_target(caster, spell, previous, selected, opts) do
      nil -> selected
      guid -> jump(caster, spell, guid, selected ++ [guid], remaining - 1, opts)
    end
  end

  defp next_target(caster, spell, previous, selected, opts) do
    case World.position(previous) do
      {world, x, y, z} ->
        now = Time.now()
        los? = Keyword.get(opts, :line_of_sight?, &line_of_sight?/2)

        candidates =
          for table <- [:players, :mobs],
              {guid, distance} <- World.nearby_units_exact(table, world, {x, y, z}, @jump_radius, now),
              guid not in selected,
              metadata = Metadata.get(guid),
              valid?(caster, spell, guid, metadata),
              visible?(caster, guid, metadata, now),
              Spell.attribute?(spell, :ignore_line_of_sight) or los?.(previous, guid),
              do: {guid, distance, metadata}

        candidates
        |> Enum.min_by(&priority(&1, spell, previous), fn -> nil end)
        |> picked_guid()

      _ ->
        nil
    end
  end

  defp valid?(caster, spell, guid, %{alive?: true} = metadata) do
    creature_type_allowed?(spell, metadata) and allegiance_allowed?(caster, spell, guid, metadata)
  end

  defp valid?(_caster, _spell, _guid, _metadata), do: false

  defp creature_type_allowed?(spell, metadata) do
    Spell.creature_type_mask_ignored?(spell) or
      Spell.creature_type_allowed?(spell, Map.get(metadata, :creature_type))
  end

  defp allegiance_allowed?(caster, spell, guid, metadata) do
    if Spell.requires_hostile_target?(spell) do
      Hostility.valid_attack_target?(caster, guid) and Hostility.can_attack_without_flagging?(caster, guid)
    else
      Hostility.friendly?(caster, Map.put(metadata, :guid, guid)) and Hostility.can_assist?(caster, guid) and
        (not Chain.healing?(spell) or Map.get(metadata, :health_deficit, 0) > 0)
    end
  end

  defp priority({guid, distance, metadata}, spell, previous) do
    if Chain.healing?(spell) do
      {not same_raid?(previous, guid), -Map.get(metadata, :health_deficit, 0), distance, guid}
    else
      {distance, guid}
    end
  end

  defp same_raid?(previous, guid) do
    case PartySystem.group_of(previous) do
      %{members: members} -> Enum.any?(members, &(&1.guid == guid))
      _ -> false
    end
  end

  defp visible?(caster, guid, metadata, now) do
    case {World.position(caster, now), World.position(guid, now)} do
      {{world, x, y, z}, {world, tx, ty, tz}} ->
        detector = detector(caster)
        orientation = elem(caster.movement_block.position, 3)
        distance = Math.distance({x, y, z}, {tx, ty, tz})
        behind? = Math.behind?({x, y, orientation}, {tx, ty})
        StealthDetection.detectable?(detector, metadata, distance, now, behind?)

      _ ->
        false
    end
  end

  defp detector(%{unit: _unit} = caster) do
    caster |> StealthDetection.target_metadata() |> Map.put(:guid, caster.object.guid)
  end

  defp detector(caster), do: Map.put(Metadata.get(caster.object.guid) || %{}, :guid, caster.object.guid)

  defp line_of_sight?(source, target) do
    case {World.position(source), World.position(target)} do
      {{world, x, y, z}, {world, tx, ty, tz}} ->
        Pathfinding.line_of_sight?(world.map_id, {x, y, z}, {tx, ty, tz})

      _ ->
        false
    end
  end

  defp picked_guid({guid, _distance, _metadata}), do: guid
  defp picked_guid(nil), do: nil
end
