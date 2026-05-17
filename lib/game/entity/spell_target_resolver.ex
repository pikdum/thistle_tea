defmodule ThistleTea.Game.Entity.SpellTargetResolver do
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World

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
    |> Enum.filter(fn {guid, _distance} -> Hostility.valid_hostile_target?(caster, guid) end)
    |> Enum.map(fn {guid, _distance} -> guid end)
  end
end
