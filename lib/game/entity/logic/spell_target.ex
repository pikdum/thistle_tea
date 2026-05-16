defmodule ThistleTea.Game.Entity.Logic.SpellTarget do
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def resolve(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, %Targets{} = targets) do
    resolve_query(caster, caster_guid, target_query(spell, targets))
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

  def target_query(%Spell{} = spell, %Targets{} = targets) do
    cond do
      caster_aoe_spell?(spell) ->
        {:caster_aoe, max_aoe_radius(spell)}

      targeted_aoe_spell?(spell) and is_tuple(Targets.ground_location(targets)) ->
        {:targeted_aoe, Targets.ground_location(targets), max_aoe_radius(spell)}

      is_integer(targets.unit_guid) ->
        {:unit, targets.unit_guid}

      true ->
        :none
    end
  end

  def target_query(_spell, _targets), do: :none

  defp caster_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_at_caster]))
  end

  defp targeted_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_at_dest, :aoe_enemy_at_channel]))
  end

  defp effect_targets?(%Effect{} = effect, targets) do
    effect.implicit_target_a in targets or effect.implicit_target_b in targets
  end

  defp max_aoe_radius(%Spell{effects: effects}) do
    effects
    |> Enum.map(& &1.radius_yards)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> 0.0 end)
  end

  defp nearby_enemy_guids(caster, caster_guid, radius) when is_number(radius) and radius > 0 do
    caster
    |> nearby_hostiles(radius)
    |> living_guids(caster_guid)
  end

  defp nearby_enemy_guids(_caster, _caster_guid, _radius), do: []

  defp nearby_enemy_guids_at(%{internal: %{map: map}}, caster_guid, {x, y, z}, radius)
       when is_number(radius) and radius > 0 do
    map
    |> nearby_hostiles_at(caster_guid, {x, y, z}, radius)
    |> living_guids(caster_guid)
  end

  defp nearby_enemy_guids_at(_caster, _caster_guid, _position, _radius), do: []

  defp nearby_hostiles(%{object: %{guid: guid}} = caster, radius) do
    case Guid.entity_type(guid) do
      :mob -> World.nearby_players(caster, radius)
      :player -> World.nearby_mobs(caster, radius)
      _ -> World.nearby_mobs(caster, radius)
    end
  end

  defp nearby_hostiles_at(map, caster_guid, position, radius) do
    case Guid.entity_type(caster_guid) do
      :mob -> World.nearby_players_at(map, position, radius)
      :player -> World.nearby_mobs_at(map, position, radius)
      _ -> World.nearby_mobs_at(map, position, radius)
    end
  end

  defp living_guids(results, caster_guid) do
    results
    |> Enum.reject(fn {guid, _distance} -> guid == caster_guid end)
    |> Enum.filter(fn {guid, _distance} -> alive_target?(guid) end)
    |> Enum.map(fn {guid, _distance} -> guid end)
  end

  defp alive_target?(guid) when is_integer(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> false
      _ -> true
    end
  end

  defp alive_target?(_guid), do: false
end
