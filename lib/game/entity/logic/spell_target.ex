defmodule ThistleTea.Game.Entity.Logic.SpellTarget do
  @moduledoc """
  Classifies a spell + targets blob into a target query — caster AoE, cone,
  ground-targeted AoE, or a single unit — for the spatial target resolver.
  Also resolves triggered-spell targets from their implicit target data,
  including caster procs and self-targeted enemy channel procs.
  """
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets

  def target_query(%Spell{} = spell, %Targets{} = targets) do
    cond do
      caster_aoe_spell?(spell) ->
        {:caster_aoe, max_aoe_radius(spell)}

      cone_aoe_spell?(spell) ->
        {:caster_cone, max_aoe_radius(spell)}

      targeted_aoe_spell?(spell) and is_tuple(Targets.ground_location(targets)) ->
        {:targeted_aoe, Targets.ground_location(targets), max_aoe_radius(spell)}

      party_aoe_spell?(spell) ->
        {:party_aoe, max_aoe_radius(spell)}

      is_integer(targets.unit_guid) ->
        {:unit, targets.unit_guid}

      true ->
        :none
    end
  end

  def target_query(_spell, _targets), do: :none

  def area_targeted?(%Spell{} = spell) do
    caster_aoe_spell?(spell) or cone_aoe_spell?(spell) or targeted_aoe_spell?(spell) or party_aoe_spell?(spell)
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

  defp targeted_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_at_dest, :aoe_enemy_at_channel]))
  end

  defp party_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:party_around_caster]))
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
end
