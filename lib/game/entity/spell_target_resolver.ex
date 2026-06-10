defmodule ThistleTea.Game.Entity.SpellTargetResolver do
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpatialHash

  @cone_arc_radians :math.pi() / 3

  def resolve(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, %Targets{} = targets) do
    resolve_query(caster, caster_guid, SpellTarget.target_query(spell, targets))
  end

  def resolve(_caster, _spell, _targets), do: []

  def resolve_query(%{object: %{guid: caster_guid}} = caster, query) do
    resolve_query(caster, caster_guid, query)
  end

  def resolve_query(_caster, _query), do: []

  defp resolve_query(caster, caster_guid, query) do
    case query do
      {:caster_aoe, radius} ->
        nearby_enemy_guids(caster, caster_guid, radius)

      {:caster_cone, radius} ->
        nearby_cone_enemy_guids(caster, caster_guid, radius)

      {:targeted_aoe, position, radius} ->
        nearby_enemy_guids_at(caster, caster_guid, position, radius)

      {:unit, guid} ->
        [guid]

      :none ->
        []
    end
  end

  defp nearby_enemy_guids(caster, caster_guid, radius) when is_number(radius) and radius > 0 do
    caster
    |> nearby_units(radius)
    |> hostile_living_guids(caster, caster_guid)
  end

  defp nearby_enemy_guids(_caster, _caster_guid, _radius), do: []

  defp nearby_cone_enemy_guids(%{movement_block: %{position: {x, y, _z, orientation}}} = caster, caster_guid, radius)
       when is_number(radius) and radius > 0 do
    caster
    |> nearby_units(radius)
    |> hostile_living_guids(caster, caster_guid)
    |> Enum.filter(&in_cone?(&1, {x, y}, orientation))
  end

  defp nearby_cone_enemy_guids(_caster, _caster_guid, _radius), do: []

  defp in_cone?(guid, {x, y}, orientation) do
    case SpatialHash.get_entity(guid) do
      {_guid, _map, tx, ty, _tz} ->
        angle = :math.atan2(ty - y, tx - x)
        abs(normalize_angle(angle - orientation)) <= @cone_arc_radians / 2

      _ ->
        false
    end
  end

  defp normalize_angle(angle) do
    two_pi = 2 * :math.pi()
    angle = :math.fmod(angle, two_pi)

    cond do
      angle > :math.pi() -> angle - two_pi
      angle < -:math.pi() -> angle + two_pi
      true -> angle
    end
  end

  defp nearby_enemy_guids_at(%{internal: %{map: map}} = caster, caster_guid, {x, y, z}, radius)
       when is_number(radius) and radius > 0 do
    map
    |> nearby_units_at({x, y, z}, radius)
    |> hostile_living_guids(caster, caster_guid)
  end

  defp nearby_enemy_guids_at(_caster, _caster_guid, _position, _radius), do: []

  defp nearby_units(caster, radius) do
    World.nearby_players(caster, radius) ++ World.nearby_mobs(caster, radius)
  end

  defp nearby_units_at(map, position, radius) do
    World.nearby_players_at(map, position, radius) ++ World.nearby_mobs_at(map, position, radius)
  end

  defp hostile_living_guids(results, caster, caster_guid) do
    results
    |> Enum.reject(fn {guid, _distance} -> guid == caster_guid end)
    |> Enum.filter(fn {guid, _distance} -> Hostility.valid_attack_target?(caster, guid) end)
    |> Enum.map(fn {guid, _distance} -> guid end)
  end
end
