defmodule ThistleTea.Game.Entity.SpellTargetResolver do
  @moduledoc """
  Boundary that resolves a spell's target query into concrete guids using
  spatial lookups and hostility checks.
  """
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @cone_arc_radians :math.pi() / 3

  def resolve(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, %Targets{} = targets) do
    query = pet_target_query(caster, spell) || SpellTarget.target_query(spell, targets)

    caster
    |> resolve_query(caster_guid, query)
    |> Enum.filter(&creature_type_allowed?(spell, &1))
  end

  def resolve(_caster, _spell, _targets), do: []

  defp pet_target_query(%{unit: %{summon: pet_guid}}, %Spell{effects: effects})
       when is_integer(pet_guid) and pet_guid > 0 do
    if Enum.any?(effects, &(&1.implicit_target_a == :pet or &1.implicit_target_b == :pet)) do
      {:unit, pet_guid}
    end
  end

  defp pet_target_query(_caster, _spell), do: nil

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

      {:party_aoe, radius} ->
        nearby_party_guids(caster, caster_guid, radius)

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
    case World.position(guid) do
      {_map, tx, ty, _tz} ->
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

  defp nearby_units(
         %{object: %{guid: self_guid}, internal: %{map: map}, movement_block: %{position: {x, y, z, _o}}},
         radius
       ) do
    nearby_units_at(map, {x, y, z}, radius)
    |> Enum.reject(fn {guid, _distance} -> guid == self_guid end)
  end

  defp nearby_units_at(map, position, radius) do
    World.nearby_units_exact(:players, map, position, radius) ++
      World.nearby_units_exact(:mobs, map, position, radius)
  end

  defp hostile_living_guids(results, caster, caster_guid) do
    results
    |> Enum.reject(fn {guid, _distance} -> guid == caster_guid end)
    |> Enum.filter(fn {guid, _distance} -> Hostility.valid_attack_target?(caster, guid) end)
    |> Enum.map(fn {guid, _distance} -> guid end)
  end

  defp nearby_party_guids(caster, caster_guid, radius) when is_number(radius) and radius > 0 do
    members =
      case PartySystem.group_of(caster_guid) do
        %Party.Group{} = group ->
          member_guids = MapSet.new(group.members, & &1.guid)

          caster
          |> nearby_units(radius)
          |> Enum.map(fn {guid, _distance} -> guid end)
          |> Enum.filter(fn guid -> MapSet.member?(member_guids, guid) and alive?(guid) end)

        _ ->
          []
      end

    [caster_guid | members]
  end

  defp nearby_party_guids(_caster, caster_guid, _radius), do: [caster_guid]

  defp alive?(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: alive?} -> alive? == true
      _ -> false
    end
  end

  defp creature_type_allowed?(%Spell{target_creature_type_mask: mask}, _guid) when mask in [0, nil], do: true

  defp creature_type_allowed?(%Spell{} = spell, guid) do
    case Metadata.query(guid, [:creature_type]) do
      %{creature_type: creature_type} -> Spell.creature_type_allowed?(spell, creature_type)
      _ -> false
    end
  end
end
