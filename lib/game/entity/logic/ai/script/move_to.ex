defmodule ThistleTea.Game.Entity.Logic.AI.Script.MoveTo do
  @moduledoc """
  Decodes absolute, target-relative, and random-point script movement into a navigation request, retaining point
  identity, travel time, movement mode, and final facing through the spline.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement

  @default_object_radius 0.389

  def apply(%Mob{} = mob, %ScriptStep{} = step, target, %Context{} = context) do
    with false <- Core.dead?(mob),
         true <- not Movement.blocked?(mob) or (step.datalong4 &&& 1) != 0,
         mob = Movement.sync_position(mob, context.now),
         {:ok, position} <- destination(mob, step, target, context) do
      {:ok, enqueue(mob, %{step | position: position})}
    else
      _ -> :error
    end
  end

  def apply(_entity, %ScriptStep{}, _target, %Context{}), do: :error

  defp destination(_mob, %ScriptStep{datalong: 0, position: position}, _target, _context), do: {:ok, position}

  defp destination(
         %Mob{internal: %{world: world}} = mob,
         %ScriptStep{datalong: mode} = step,
         target,
         %Context{perception: perception} = context
       )
       when mode in [1, 2] do
    case Perception.position(perception, target) do
      {^world, x, y, z} -> {:ok, relative_position(mob, step, {x, y, z}, target, context)}
      _ -> :error
    end
  end

  defp destination(
         %Mob{internal: %{world: world}},
         %ScriptStep{datalong: 3, position: {x, y, z, radius}},
         _target,
         %Context{navigation: navigation}
       ) do
    anchor = {x, y, z}
    {x, y, z} = Navigation.find_random_point(navigation, world.map_id, anchor, radius) || anchor
    {:ok, {x, y, z, -10.0}}
  end

  defp destination(_mob, _step, _target, _context), do: :error

  defp relative_position(_mob, %ScriptStep{datalong: 1, position: {dx, dy, dz, o}}, {x, y, z}, _target, _context) do
    {x + dx, y + dy, z + dz, o}
  end

  defp relative_position(mob, %ScriptStep{position: {distance, _, _, orientation}}, {x, y, z}, target, context) do
    {sx, sy, _, _} = mob.movement_block.position
    angle = if orientation < 0, do: :math.atan2(sy - y, sx - x), else: Random.float(context.random) * 2 * :math.pi()
    metadata = Perception.metadata(context.perception, target) || %{}
    distance = distance + (Map.get(metadata, :bounding_radius) || @default_object_radius)
    {x + distance * :math.cos(angle), y + distance * :math.sin(angle), z, orientation}
  end

  def request(%ScriptStep{command: :move_to, datalong: 3, position: {x, y, z, radius}})
      when is_number(radius) and radius >= 0.1, do: [{{x, y, z}, radius}]

  def request(%ScriptStep{}), do: []

  defp enqueue(%Mob{} = mob, %ScriptStep{position: {x, y, z, orientation}} = step) do
    opts = [
      pathfind?: (step.datalong3 &&& 1) != 0,
      allow_steep: (step.datalong3 &&& 128) == 0,
      travel_time: step.datalong2,
      flying?: (step.datalong3 &&& 8) != 0
    ]

    opts = movement_mode(opts, step.datalong3)
    opts = if orientation > 0, do: Keyword.put(opts, :face_angle, orientation), else: opts
    opts = point_callback(opts, step)
    NavigationIntent.enqueue(mob, {x, y, z}, opts)
  end

  defp movement_mode(opts, flags) when (flags &&& 4) != 0, do: Keyword.put(opts, :run?, true)
  defp movement_mode(opts, flags) when (flags &&& 2) != 0, do: Keyword.put(opts, :run?, false)
  defp movement_mode(opts, _flags), do: opts

  defp point_callback(opts, %ScriptStep{datalong4: flags, dataint: point_id}) when (flags &&& 2) != 0 do
    Keyword.put(opts, :movement_inform, %Effects.MovementInform{motion_type: 9, point_id: point_id})
  end

  defp point_callback(opts, %ScriptStep{}), do: opts
end
