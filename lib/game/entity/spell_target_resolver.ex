defmodule ThistleTea.Game.Entity.SpellTargetResolver do
  @moduledoc """
  Boundary that resolves a spell's target query into concrete guids using
  spatial lookups and hostility checks.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @cone_arc_radians :math.pi() / 3
  @chain_jump_radius 10.0

  def resolve(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, %Targets{} = targets) do
    query = pet_target_query(caster, spell) || SpellTarget.target_query(spell, targets)

    initial =
      caster
      |> resolve_query(caster_guid, query)
      |> Enum.filter(&creature_type_allowed?(spell, &1))

    caster
    |> expand_chain(spell, initial)
    |> append_caster_execution_target(spell, caster_guid)
  end

  def resolve(_caster, _spell, _targets), do: []

  defp expand_chain(caster, %Spell{} = spell, [first | _] = initial) do
    count = spell.effects |> Enum.map(&(&1.chain_targets || 0)) |> Enum.max(fn -> 0 end)

    if count > 1 do
      chain_targets(caster, spell, first, Enum.uniq(initial), count - length(initial))
    else
      initial
    end
  end

  defp expand_chain(_caster, _spell, initial), do: initial

  defp append_caster_execution_target(targets, %Spell{effects: effects}, caster_guid) do
    if Enum.any?(effects, &caster_execution_effect?/1) do
      Enum.uniq(targets ++ [caster_guid])
    else
      targets
    end
  end

  defp caster_execution_effect?(%{implicit_target_a: :caster}), do: true
  defp caster_execution_effect?(%{implicit_target_b: :caster}), do: true
  defp caster_execution_effect?(%{type: :summon_demon, implicit_target_a: nil, implicit_target_b: nil}), do: true
  defp caster_execution_effect?(_effect), do: false

  defp chain_targets(_caster, _spell, _previous, selected, remaining) when remaining <= 0, do: selected

  defp chain_targets(caster, spell, previous, selected, remaining) do
    case next_chain_target(caster, spell, previous, selected) do
      nil -> selected
      guid -> chain_targets(caster, spell, guid, selected ++ [guid], remaining - 1)
    end
  end

  defp next_chain_target(caster, spell, previous, selected) do
    case World.position(previous) do
      {map, x, y, z} ->
        ((:players |> World.nearby_units_exact(map, {x, y, z}, @chain_jump_radius)) ++
           (:mobs |> World.nearby_units_exact(map, {x, y, z}, @chain_jump_radius)))
        |> Enum.reject(fn {guid, _distance} -> guid in selected end)
        |> Enum.filter(fn {guid, _distance} -> valid_chain_target?(caster, spell, guid) end)
        |> pick_chain_target(spell)

      _ ->
        nil
    end
  end

  defp pick_chain_target(candidates, %Spell{} = spell) do
    picked =
      if Spell.requires_hostile_target?(spell) do
        Enum.min_by(candidates, &elem(&1, 1), fn -> nil end)
      else
        Enum.min_by(candidates, &health_pct(elem(&1, 0)), fn -> nil end)
      end

    case picked do
      {guid, _distance} -> guid
      nil -> nil
    end
  end

  defp health_pct(guid) do
    case Metadata.query(guid, [:health_pct]) do
      %{health_pct: pct} when is_number(pct) -> pct
      _ -> 100.0
    end
  end

  defp valid_chain_target?(caster, %Spell{} = spell, guid) do
    if Spell.requires_hostile_target?(spell) do
      Hostility.valid_attack_target?(caster, guid)
    else
      case Metadata.query(guid, [:alive?]) do
        %{alive?: true} -> Hostility.friendly?(caster, Metadata.query(guid, [:faction_template]))
        _ -> false
      end
    end
  end

  defp pet_target_query(%Character{} = caster, %Spell{effects: effects}) do
    pet_guid = Character.controlled_guid(caster)

    if Enum.any?(effects, &(&1.implicit_target_a == :pet or &1.implicit_target_b == :pet)) do
      if is_integer(pet_guid), do: {:unit, pet_guid}
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

      {:party_class_aoe, class_guid, radius} ->
        party_class_guids(caster, caster_guid, class_guid, radius)

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

  defp nearby_enemy_guids_at(%{internal: %{world: world}} = caster, caster_guid, {x, y, z}, radius)
       when is_number(radius) and radius > 0 do
    world
    |> nearby_units_at({x, y, z}, radius)
    |> hostile_living_guids(caster, caster_guid)
  end

  defp nearby_enemy_guids_at(_caster, _caster_guid, _position, _radius), do: []

  defp nearby_units(
         %{object: %{guid: self_guid}, internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}},
         radius
       ) do
    nearby_units_at(world, {x, y, z}, radius)
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
    party_guid = party_owner_guid(caster, caster_guid)
    nearby_guids = caster |> nearby_units(radius) |> Enum.map(fn {guid, _distance} -> guid end)

    members =
      case PartySystem.group_of(party_guid) do
        %Party.Group{} = group ->
          member_guids = MapSet.new(group.members, & &1.guid)

          nearby_guids
          |> Enum.filter(fn guid -> MapSet.member?(member_guids, guid) and alive?(guid) end)

        _ ->
          Enum.filter(nearby_guids, &(&1 == party_guid and alive?(&1)))
      end

    if party_guid == caster_guid, do: Enum.uniq([caster_guid | members]), else: Enum.uniq(members)
  end

  defp nearby_party_guids(_caster, caster_guid, _radius), do: [caster_guid]

  defp party_owner_guid(%{unit: %{created_by: owner_guid}}, _caster_guid)
       when is_integer(owner_guid) and owner_guid > 0, do: owner_guid

  defp party_owner_guid(_caster, caster_guid), do: caster_guid

  defp alive?(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: alive?} -> alive? == true
      _ -> false
    end
  end

  defp party_class_guids(caster, caster_guid, class_guid, radius) do
    reference_class = metadata_class(class_guid || caster_guid)

    caster
    |> nearby_party_guids(caster_guid, radius)
    |> Enum.filter(&(reference_class != nil and metadata_class(&1) == reference_class))
  end

  defp metadata_class(guid) do
    case Metadata.query(guid, [:class]) do
      %{class: class} when is_integer(class) -> class
      _ -> nil
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
