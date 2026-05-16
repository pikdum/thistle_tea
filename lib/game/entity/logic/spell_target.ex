defmodule ThistleTea.Game.Entity.Logic.SpellTarget do
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def resolve(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, %Targets{} = targets) do
    cond do
      caster_aoe_spell?(spell) ->
        nearby_enemy_guids(caster, caster_guid, max_aoe_radius(spell))

      targeted_aoe_spell?(spell) and is_tuple(targets.destination_location) ->
        nearby_enemy_guids_at(caster, caster_guid, targets.destination_location, max_aoe_radius(spell))

      is_integer(targets.unit_guid) ->
        [targets.unit_guid]

      true ->
        []
    end
  end

  def resolve(_caster, _spell, _targets), do: []

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
    |> World.nearby_mobs(radius)
    |> living_guids(caster_guid)
  end

  defp nearby_enemy_guids(_caster, _caster_guid, _radius), do: []

  defp nearby_enemy_guids_at(%{internal: %{map: map}}, caster_guid, {x, y, z}, radius)
       when is_number(radius) and radius > 0 do
    map
    |> World.nearby_mobs_at({x, y, z}, radius)
    |> living_guids(caster_guid)
  end

  defp nearby_enemy_guids_at(_caster, _caster_guid, _position, _radius), do: []

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
