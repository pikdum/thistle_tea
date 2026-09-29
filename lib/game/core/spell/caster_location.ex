defmodule ThistleTea.Game.Core.Spell.CasterLocation do
  @moduledoc "Classifies caster-relative destinations and computes their orientation-relative offsets."

  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Radius

  @angles %{
    minion_position: 0.25,
    caster_front_right: 1.75,
    caster_back_right: 1.25,
    caster_back_left: 0.75,
    caster_front_left: 0.25,
    caster_front: 0.0,
    caster_back: 1.0,
    caster_left: 0.5,
    caster_right: -0.5
  }

  def required?(%Effect{} = effect), do: target(effect) != nil

  def caster_only?(%Effect{} = effect) do
    required?(effect) and
      Enum.all?([effect.implicit_target_a, effect.implicit_target_b], fn selector ->
        selector in [nil, :caster, :caster_source, :caster_destination] or is_map_key(@angles, selector)
      end)
  end

  def destination(%Effect{} = effect, {x, y, z, orientation}, modifiers \\ []) do
    case target(effect) do
      nil ->
        nil

      selector ->
        distance = if is_nil(effect.radius_yards), do: 0.0, else: Radius.effect(effect, modifiers)
        angle = orientation + Map.fetch!(@angles, selector) * :math.pi()
        {x + distance * :math.cos(angle), y + distance * :math.sin(angle), z}
    end
  end

  defp target(%Effect{type: :duel}), do: nil

  defp target(%Effect{} = effect),
    do: Enum.find([effect.implicit_target_a, effect.implicit_target_b], &is_map_key(@angles, &1))
end
