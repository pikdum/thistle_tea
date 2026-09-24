defmodule ThistleTea.Game.Entity.SpellTargetResolver do
  @moduledoc """
  Boundary that resolves a spell's target query into concrete guids using
  spatial lookups and hostility checks.
  """
  alias ThistleTea.Game.Entity.ChainTargets
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Insignia
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.AuraRank
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetLimit
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InsigniaTarget
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.ResurrectionTarget
  alias ThistleTea.Game.World.SpellMagnets
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @cone_arc_radians :math.pi() / 3

  def resolve(caster, spell, targets, opts \\ [])

  def resolve(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, %Target{} = targets, opts) do
    cond do
      Insignia.spell?(spell) ->
        case insignia_target(caster, spell, targets) do
          {:ok, guid} -> [guid]
          {:error, _reason} -> []
        end

      Spell.resurrect_spell?(spell) ->
        case resurrection_target(caster, spell, targets) do
          {:ok, guid} -> [guid]
          {:error, _reason} -> []
        end

      true ->
        resolve_targets(caster, caster_guid, spell, targets, opts)
    end
  end

  def resolve(_caster, _spell, _targets, _opts), do: []

  def insignia_target(caster, spell, targets) do
    info = InsigniaTarget.info(caster, targets)
    with :ok <- CastValidation.validate_target(caster, spell, targets, info), do: {:ok, info.body_guid}
  end

  def resurrection_target(caster, spell, targets) do
    info = ResurrectionTarget.info(caster, targets)
    with :ok <- CastValidation.validate_target(caster, spell, targets, info), do: {:ok, info.guid}
  end

  defp resolve_targets(caster, caster_guid, spell, targets, opts) do
    query =
      pet_target_query(caster, spell) || SpellTarget.target_query(spell, targets, Modifiers.snapshot(caster, spell))

    opts = [
      selected_guid: Target.unit_guid(targets),
      check_buff_level?:
        match?(%Character{}, caster) and not Spell.harmful?(spell) and not Keyword.get(opts, :triggered?, false) and
          is_nil(Keyword.get(opts, :cast_item_guid))
    ]

    initial = resolve_query(caster, spell, query, opts)

    redirected = redirect_initial(caster, spell, query, initial)
    targets = if redirected == initial, do: ChainTargets.expand(caster, spell, initial), else: redirected
    targets = Enum.filter(targets, &buff_level_allowed?(caster, spell, &1, opts))
    targets = if Spell.harmful?(spell), do: targets, else: Enum.filter(targets, &Hostility.can_assist?(caster, &1))
    append_caster_execution_target(targets, spell, caster_guid)
  end

  defp redirect_initial(caster, spell, {:unit, _guid}, [guid]) do
    [SpellMagnets.redirect(caster, spell, guid)]
  end

  defp redirect_initial(_caster, _spell, _query, targets), do: targets

  defp append_caster_execution_target(targets, %Spell{effects: effects}, caster_guid) do
    if Enum.any?(effects, &caster_execution_effect?/1) do
      Enum.uniq(targets ++ [caster_guid])
    else
      targets
    end
  end

  defp caster_execution_effect?(%{implicit_target_a: :caster}), do: true
  defp caster_execution_effect?(%{implicit_target_b: :caster}), do: true
  defp caster_execution_effect?(%{type: :dismiss_pet}), do: true
  defp caster_execution_effect?(%{type: :stuck}), do: true
  defp caster_execution_effect?(%{type: :summon_object_wild}), do: true
  defp caster_execution_effect?(%{type: :summon_mini_pet}), do: true
  defp caster_execution_effect?(%{type: :summon_guardian}), do: true
  defp caster_execution_effect?(%{type: :summon_wild}), do: true
  defp caster_execution_effect?(%{type: :summon_demon, implicit_target_a: nil, implicit_target_b: nil}), do: true
  defp caster_execution_effect?(effect), do: PetTraining.training_effect?(effect)

  defp pet_target_query(%Character{} = caster, %Spell{effects: effects}) do
    pet_guid = Character.controlled_guid(caster)

    if Enum.any?(effects, &(&1.implicit_target_a == :pet or &1.implicit_target_b == :pet)) do
      if is_integer(pet_guid), do: {:unit, pet_guid}
    end
  end

  defp pet_target_query(_caster, _spell), do: nil

  def resolve_query(%{object: %{guid: caster_guid}} = caster, query) do
    query_guids(caster, caster_guid, query)
  end

  def resolve_query(_caster, _query), do: []

  def resolve_query(caster, %Spell{} = spell, query, opts \\ []) do
    excluded = Keyword.get(opts, :exclude_guids, [])

    caster
    |> resolve_query(query)
    |> Enum.reject(&(&1 in excluded))
    |> Enum.filter(fn guid ->
      creature_type_allowed?(spell, guid) and buff_level_allowed?(caster, spell, guid, opts) and
        (Spell.harmful?(spell) or Hostility.can_assist?(caster, guid))
    end)
    |> limit_targets(spell, Keyword.get(opts, :selected_guid))
  end

  defp buff_level_allowed?(%{object: %{guid: guid}}, _spell, guid, _opts), do: true

  defp buff_level_allowed?(_caster, spell, guid, opts) do
    not Keyword.get(opts, :check_buff_level?, false) or guid == Keyword.get(opts, :selected_guid) or
      AuraRank.party_aura?(spell) or AuraRank.eligible?(spell, Map.get(Metadata.get(guid) || %{}, :level))
  end

  defp limit_targets(candidates, %Spell{max_targets: limit} = spell, primary_guid)
       when is_integer(limit) and limit > 0 do
    candidates = Enum.uniq(candidates)
    candidates = if length(candidates) > limit, do: Enum.shuffle(candidates), else: candidates
    TargetLimit.select(candidates, spell, primary_guid)
  end

  defp limit_targets(candidates, _spell, _primary_guid), do: Enum.uniq(candidates)

  defp query_guids(caster, caster_guid, {:party_unit, guid}), do: party_unit_guids(caster, caster_guid, guid)

  defp query_guids(caster, caster_guid, :caster_master) do
    case party_owner_guid(caster, caster_guid) do
      owner_guid when is_integer(owner_guid) and owner_guid != caster_guid -> [owner_guid]
      _ -> []
    end
  end

  defp query_guids(caster, caster_guid, {:unit_and_master, unit_guid}) do
    query_guids(caster, caster_guid, :caster_master) ++ [unit_guid]
  end

  defp query_guids(caster, _caster_guid, {:caster_friendly_aoe, radius}) do
    case caster_position(caster, Time.now()) do
      {_world, x, y, z} -> nearby_friendly_guids_at(caster, {x, y, z}, radius)
      nil -> []
    end
  end

  defp query_guids(caster, _caster_guid, {:targeted_friendly_aoe, position, radius}) do
    nearby_friendly_guids_at(caster, position, radius)
  end

  defp query_guids(caster, caster_guid, query) do
    case query do
      {:caster_aoe, radius} ->
        nearby_enemy_guids(caster, caster_guid, radius)

      {:caster_cone, radius} ->
        nearby_cone_enemy_guids(caster, caster_guid, radius)

      {:targeted_aoe, position, radius} ->
        nearby_enemy_guids_at(caster, caster_guid, position, radius)

      {:party_aoe, radius} ->
        nearby_party_guids(caster, caster_guid, radius)

      {:target_party_aoe, target_guid, radius} ->
        target_party_guids(target_guid, radius)

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

  defp nearby_cone_enemy_guids(%{movement_block: %{position: {_x, _y, _z, orientation}}} = caster, caster_guid, radius)
       when is_number(radius) and radius > 0 do
    now = Time.now()

    case caster_position(caster, now) do
      {world, x, y, z} ->
        world
        |> nearby_units_at({x, y, z}, radius, now)
        |> hostile_living_guids(caster, caster_guid)
        |> Enum.filter(&in_cone?(&1, {x, y}, orientation))

      nil ->
        []
    end
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

  defp nearby_friendly_guids_at(%{internal: %{world: world}} = caster, position, radius)
       when is_number(radius) and radius > 0 do
    world
    |> nearby_units_at(position, radius)
    |> Enum.filter(fn {guid, _distance} ->
      case Metadata.get(guid) do
        %{alive?: true} = metadata -> Hostility.friendly?(caster, Map.put(metadata, :guid, guid))
        _ -> false
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp nearby_friendly_guids_at(_caster, _position, _radius), do: []

  defp nearby_units(%{object: %{guid: self_guid}} = caster, radius) do
    now = Time.now()

    case caster_position(caster, now) do
      {world, x, y, z} -> nearby_units_at(world, {x, y, z}, radius, now)
      nil -> []
    end
    |> Enum.reject(fn {guid, _distance} -> guid == self_guid end)
  end

  defp nearby_units_at(map, position, radius) do
    nearby_units_at(map, position, radius, Time.now())
  end

  defp nearby_units_at(map, position, radius, now) do
    World.nearby_units_exact(:players, map, position, radius, now) ++
      World.nearby_units_exact(:mobs, map, position, radius, now)
  end

  defp caster_position(%{object: %{guid: guid}} = caster, now) when is_integer(guid) do
    World.position(caster, now)
  end

  defp caster_position(_caster, _now), do: nil

  defp hostile_living_guids(results, caster, caster_guid) do
    results
    |> Enum.reject(fn {guid, _distance} -> guid == caster_guid end)
    |> Enum.filter(fn {guid, _distance} ->
      Hostility.valid_attack_target?(caster, guid, area?: true) and Hostility.can_attack_without_flagging?(caster, guid)
    end)
    |> Enum.map(fn {guid, _distance} -> guid end)
  end

  defp nearby_party_guids(caster, caster_guid, radius, scope \\ :subgroup)

  defp nearby_party_guids(caster, caster_guid, radius, scope) when is_number(radius) and radius > 0 do
    party_guid = party_owner_guid(caster, caster_guid)
    nearby_guids = caster |> nearby_units(radius) |> Enum.map(fn {guid, _distance} -> guid end)

    members =
      case PartySystem.group_of(party_guid) do
        %Party.Group{} = group ->
          members = if scope == :raid, do: group.members, else: Party.subgroup_members(group, party_guid)
          MapSet.new(members, & &1.guid)

        _ ->
          MapSet.new([party_guid])
      end

    [caster_guid | nearby_guids]
    |> Enum.uniq()
    |> Enum.filter(fn guid ->
      (guid == caster_guid and party_guid == caster_guid) or
        (alive?(guid) and (MapSet.member?(members, guid) or party_pet?(guid, members)))
    end)
  end

  defp nearby_party_guids(_caster, caster_guid, _radius, _scope), do: [caster_guid]

  defp target_party_guids(target_guid, radius) when is_number(radius) and radius > 0 do
    with owner_guid when is_integer(owner_guid) <- target_party_owner(target_guid),
         {world, x, y, z} <- World.position(owner_guid) do
      members =
        case PartySystem.group_of(owner_guid) do
          %Party.Group{} = group ->
            group
            |> Party.subgroup_members(owner_guid)
            |> MapSet.new(& &1.guid)

          _ ->
            MapSet.new([owner_guid])
        end

      world
      |> nearby_units_at({x, y, z}, radius)
      |> Enum.map(&elem(&1, 0))
      |> then(&[owner_guid | &1])
      |> Enum.uniq()
      |> Enum.filter(&(alive?(&1) and (MapSet.member?(members, &1) or party_pet?(&1, members))))
    else
      _ -> []
    end
  end

  defp target_party_guids(_target_guid, _radius), do: []

  defp party_unit_guids(caster, caster_guid, target_guid) do
    owner_guid = party_owner_guid(caster, caster_guid)
    target_owner_guid = target_party_owner(target_guid)

    if alive?(target_guid) and party_unit_allowed?(caster_guid, target_guid, owner_guid, target_owner_guid),
      do: [target_guid],
      else: []
  end

  defp party_unit_allowed?(caster_guid, target_guid, _owner_guid, _target_owner_guid) when caster_guid == target_guid,
    do: false

  defp party_unit_allowed?(_caster_guid, _target_guid, _owner_guid, target_owner_guid)
       when not is_integer(target_owner_guid), do: false

  defp party_unit_allowed?(caster_guid, target_guid, owner_guid, target_owner_guid) do
    target_guid == owner_guid or
      (owner_guid == caster_guid and owner_guid == target_owner_guid) or
      group_member?(owner_guid, target_owner_guid)
  end

  defp group_member?(owner_guid, target_owner_guid) do
    case PartySystem.group_of(owner_guid) do
      %Party.Group{} = group -> Party.member(group, target_owner_guid) != nil
      _ -> false
    end
  end

  defp target_party_owner(guid) do
    cond do
      Guid.high_guid(guid) == Guid.high_guid(:player) ->
        guid

      Guid.high_guid(guid) == Guid.high_guid(:pet) ->
        case Metadata.query(guid, [:owner_guid]) do
          %{owner_guid: owner_guid} when is_integer(owner_guid) -> owner_guid
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp party_pet?(guid, members) do
    Guid.high_guid(guid) == Guid.high_guid(:pet) and
      case Metadata.query(guid, [:owner_guid]) do
        %{owner_guid: owner} -> MapSet.member?(members, owner)
        _ -> false
      end
  end

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
    |> nearby_party_guids(caster_guid, radius, :raid)
    |> Enum.filter(&(reference_class != nil and metadata_class(&1) == reference_class))
  end

  defp metadata_class(guid) do
    case Metadata.query(guid, [:class]) do
      %{class: class} when is_integer(class) -> class
      _ -> nil
    end
  end

  defp creature_type_allowed?(%Spell{} = spell, guid) do
    Spell.creature_type_mask_ignored?(spell) or creature_type_matches?(spell, guid)
  end

  defp creature_type_matches?(%Spell{target_creature_type_mask: mask}, _guid) when mask in [0, nil], do: true

  defp creature_type_matches?(%Spell{} = spell, guid) do
    case Metadata.query(guid, [:creature_type]) do
      %{creature_type: creature_type} -> Spell.creature_type_allowed?(spell, creature_type)
      _ -> false
    end
  end
end
