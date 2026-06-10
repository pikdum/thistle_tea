defmodule ThistleTea.Game.Entity.Logic.SpellTarget do
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

  defp cone_aoe_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, &effect_targets?(&1, [:aoe_enemy_in_cone]))
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
end
