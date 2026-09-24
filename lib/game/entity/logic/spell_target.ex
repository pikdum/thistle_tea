defmodule ThistleTea.Game.Entity.Logic.SpellTarget do
  @moduledoc """
  Classifies a spell + targets blob into a target query — caster AoE, cone,
  ground-targeted AoE, or a single unit — for the spatial target resolver.
  Also resolves triggered-spell targets from their implicit target data,
  including caster procs and self-targeted enemy channel procs.
  """
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Radius
  alias ThistleTea.Game.Spell.Target

  def target_query(spell, targets, modifiers \\ [])

  def target_query(%Spell{} = spell, %Target{} = targets, modifiers) do
    effects = Enum.reject(spell.effects, &(&1.type == :activate_object))

    if effects == [] and spell.effects != [],
      do: :none,
      else: unit_target_query(%{spell | effects: effects}, targets, modifiers)
  end

  def target_query(_spell, _targets, _modifiers), do: :none

  defp unit_target_query(spell, targets, modifiers) do
    radius = Radius.maximum(spell.effects, modifiers)
    unit_guid = Target.unit_guid(targets)

    cond do
      query = area_query(spell, targets, radius) ->
        query

      query = party_query(spell, unit_guid, radius) ->
        query

      query = master_query(spell, unit_guid) ->
        query

      raid_class_aoe_spell?(spell) ->
        {:party_class_aoe, unit_guid, raid_class_radius(spell, modifiers)}

      query = direct_unit_query(spell, unit_guid) ->
        query

      true ->
        :none
    end
  end

  defp area_query(spell, targets, radius) do
    cond do
      caster_aoe_spell?(spell) -> {:caster_aoe, radius}
      cone_aoe_spell?(spell) -> {:caster_cone, radius}
      query = targeted_aoe_query(spell, targets, radius) -> query
      true -> friendly_aoe_query(spell, targets, radius)
    end
  end

  def area_targeted?(%Spell{} = spell) do
    caster_aoe_spell?(spell) or cone_aoe_spell?(spell) or targeted_aoe_spell?(spell) or party_aoe_spell?(spell) or
      target_party_aoe_spell?(spell) or friendly_aoe_spell?(spell)
  end

  def area_targeted?(_spell), do: false

  def redirect_trigger_target(%{object: %{guid: guid}, unit: unit}, target_guid, %Spell{effects: effects})
      when target_guid == guid do
    cond do
      Enum.any?(effects, &effect_targets?(&1, [:caster])) -> guid
      not Enum.any?(effects, &(&1.implicit_target_a == :target_enemy)) -> target_guid
      enemy_guid = preferred_enemy_guid(unit, guid) -> enemy_guid
      true -> nil
    end
  end

  def redirect_trigger_target(%{object: %{guid: guid}}, target_guid, %Spell{effects: effects}) do
    if Enum.any?(effects, &effect_targets?(&1, [:caster])), do: guid, else: target_guid
  end

  def redirect_trigger_target(_entity, target_guid, _spell), do: target_guid

  defp preferred_enemy_guid(%{channel_object: channel_object, target: target}, self_guid) do
    cond do
      is_integer(channel_object) and channel_object > 0 and channel_object != self_guid -> channel_object
      is_integer(target) and target > 0 and target != self_guid -> target
      true -> nil
    end
  end

  defp preferred_enemy_guid(_unit, _self_guid), do: nil

  defp caster_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_at_caster]))
  end

  defp cone_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_in_cone]))
  end

  defp targeted_aoe_query(%Spell{} = spell, %Target{} = targets, radius) do
    cond do
      not targeted_aoe_spell?(spell) ->
        nil

      is_tuple(Target.ground_location(targets)) ->
        {:targeted_aoe, Target.ground_location(targets), radius}

      caster_destination_spell?(spell) ->
        {:caster_aoe, radius}

      true ->
        nil
    end
  end

  defp targeted_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_at_dest, :aoe_enemy_at_channel]))
  end

  defp caster_destination_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:caster_destination]))
  end

  defp friendly_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_ally_at_source, :aoe_ally_at_dest]))
  end

  defp friendly_aoe_query(%Spell{effects: effects} = spell, %Target{} = targets, radius) do
    cond do
      Enum.any?(effects, &effect_targets?(&1, [:aoe_ally_at_source])) ->
        source =
          if !Enum.any?(effects, &effect_targets?(&1, [:caster_source])), do: targets.source_location

        friendly_area_query(source, radius)

      Enum.any?(effects, &effect_targets?(&1, [:aoe_ally_at_dest])) ->
        cond do
          is_tuple(targets.destination_location) ->
            friendly_area_query(targets.destination_location, radius)

          caster_destination_spell?(spell) ->
            friendly_area_query(nil, radius)

          true ->
            :none
        end

      true ->
        nil
    end
  end

  defp friendly_area_query(nil, radius), do: {:caster_friendly_aoe, radius}
  defp friendly_area_query(position, radius), do: {:targeted_friendly_aoe, position, radius}

  defp party_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:party_around_caster]))
  end

  defp party_query(spell, unit_guid, radius) do
    cond do
      party_aoe_spell?(spell) ->
        {:party_aoe, radius}

      target_party_aoe_spell?(spell) and is_integer(unit_guid) ->
        {:target_party_aoe, unit_guid, radius}

      true ->
        nil
    end
  end

  defp target_party_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:party_around_target]))
  end

  defp caster_master_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:caster_master]))
  end

  defp master_query(spell, unit_guid) do
    cond do
      enemy_and_master_spell?(spell) and is_integer(unit_guid) -> {:unit_and_master, unit_guid}
      caster_master_spell?(spell) -> :caster_master
      true -> nil
    end
  end

  defp enemy_and_master_spell?(%Spell{effects: effects} = spell) do
    caster_master_spell?(spell) and Enum.any?(effects, &effect_targets?(&1, [:target_enemy]))
  end

  def party_member_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:party_member]))
  end

  defp direct_unit_query(spell, unit_guid) when is_integer(unit_guid) do
    if party_member_spell?(spell), do: {:party_unit, unit_guid}, else: {:unit, unit_guid}
  end

  defp direct_unit_query(_spell, _unit_guid), do: nil

  defp raid_class_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:raid_and_class]))
  end

  defp raid_class_radius(%Spell{} = spell, modifiers) do
    case Radius.maximum(spell.effects, []) do
      radius when radius > 0 -> Radius.maximum(spell.effects, modifiers)
      _ -> Radius.maximum([], modifiers, spell.range_yards || 40.0)
    end
  end

  defp effect_targets?(%Effect{type: :activate_object}, _targets), do: false

  defp effect_targets?(%Effect{} = effect, targets) do
    effect.implicit_target_a in targets or effect.implicit_target_b in targets
  end
end
