defmodule ThistleTea.Game.Core.Spell.Range do
  @moduledoc "Pure spell distances, range modifiers, and vanilla cast and movement allowances."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Modifiers

  def maximum(caster, %Spell{range_yards: range} = spell) when is_number(range) and range > 0 do
    modified(caster, spell, range)
  end

  def maximum(_caster, %Spell{range_yards: range}), do: range

  def validate(caster, %Spell{} = spell, target, opts \\ []) do
    if Keyword.get(opts, :triggered?, false), do: :ok, else: validate_distance(caster, spell, target, opts)
  end

  def allowance(%Character{}, :launch), do: 6.25
  def allowance(%Character{}, _phase), do: 1.25
  def allowance(_caster, :launch), do: 2.25
  def allowance(_caster, _phase), do: 0.0

  def combat_distance(caster, target) do
    case positions(caster, target) do
      {:ok, source, destination} ->
        {:ok, max(Math.distance(source, destination) - reach_sum(caster, target), 0.0)}

      other ->
        other
    end
  end

  defp validate_distance(caster, %Spell{range_yards: range} = spell, target, opts)
       when is_number(range) and range > 0 do
    case positions(caster, target) do
      {:ok, source, destination} -> check_distance(caster, spell, target, source, destination, opts)
      :different_world -> {:error, :out_of_range}
      :unknown -> :ok
    end
  end

  defp validate_distance(_caster, _spell, _target, _opts), do: :ok

  defp check_distance(caster, %Spell{melee_range?: true} = spell, target, {x, y, _z}, {tx, ty, _tz}, _opts) do
    modifier = Modifiers.value(caster, spell, :range, 5.0) - 5.0
    reach = max(reach_sum(caster, target, 1.5) + 2.333 + modifier, 5.0) + movement_allowance(caster, target)

    if Spell.attribute?(spell, :on_next_swing) or (tx - x) ** 2 + (ty - y) ** 2 < reach * reach,
      do: :ok,
      else: {:error, :out_of_range}
  end

  defp check_distance(caster, spell, target, source, destination, opts) do
    distance = max(Math.distance(source, destination) - reach_sum(caster, target), 0.0)

    maximum =
      maximum(caster, spell) + allowance(caster, Keyword.get(opts, :phase, :start)) + movement_allowance(caster, target)

    cond do
      distance > maximum -> {:error, :out_of_range}
      is_number(spell.min_range_yards) and distance < spell.min_range_yards -> {:error, :too_close}
      true -> :ok
    end
  end

  defp movement_allowance(%{movement_block: movement} = caster, target) do
    speed = Map.get(target, :lateral_speed, 0.0) || 0.0

    if player_involved?(caster, target) and MovementBlock.lateral_speed(movement) > 4.97 and speed > 4.97,
      do: 2.66,
      else: 0.0
  end

  defp player_involved?(%Character{}, _target), do: true
  defp player_involved?(_caster, %{guid: guid}) when is_integer(guid), do: Guid.entity_type(guid) == :player
  defp player_involved?(_caster, _target), do: false

  defp positions(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _}}}, %{
         position: {target_world, tx, ty, tz}
       }) do
    if world == target_world, do: {:ok, {x, y, z}, {tx, ty, tz}}, else: :different_world
  end

  defp positions(_caster, _target), do: :unknown

  defp reach_sum(caster, target, minimum \\ 0.0),
    do: max(caster_reach(caster), minimum) + max(Map.get(target, :combat_reach) || 0.0, minimum)

  defp caster_reach(%{unit: %{combat_reach: reach}}), do: reach || 0.0
  defp caster_reach(_caster), do: 0.0

  def channel_maximum(caster, %Spell{range_yards: range} = spell, hostile?) when is_number(range) and range > 0 do
    range = if hostile?, do: range * 1.33, else: range + 1.25
    modified(caster, spell, range)
  end

  def channel_maximum(_caster, %Spell{range_yards: range}, _hostile?), do: range

  defp modified(caster, spell, range), do: max(Modifiers.value(caster, spell, :range, range), 0.0)
end
