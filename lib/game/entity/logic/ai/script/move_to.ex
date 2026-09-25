defmodule ThistleTea.Game.Entity.Logic.AI.Script.MoveTo do
  @moduledoc """
  Decodes absolute and random-point script movement into a navigation request, retaining point
  identity, travel time, movement mode, and final facing through the spline.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement

  def apply(
        %Mob{internal: %{world: world}} = mob,
        %ScriptStep{datalong: 3, position: {x, y, z, radius}} = step,
        %Context{navigation: navigation}
      ) do
    anchor = {x, y, z}
    {x, y, z} = Navigation.find_random_point(navigation, world.map_id, anchor, radius) || anchor
    __MODULE__.apply(mob, %{step | position: {x, y, z, -10.0}})
  end

  def apply(entity, %ScriptStep{} = step, %Context{}), do: __MODULE__.apply(entity, step)

  def request(%ScriptStep{command: :move_to, datalong: 3, position: {x, y, z, radius}})
      when is_number(radius) and radius >= 0.1, do: [{{x, y, z}, radius}]

  def request(%ScriptStep{}), do: []

  def apply(%Mob{} = mob, %ScriptStep{position: {x, y, z, orientation}} = step) do
    if Core.dead?(mob) or (Movement.blocked?(mob) and (step.datalong4 &&& 1) == 0) do
      mob
    else
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
  end

  def apply(entity, %ScriptStep{}), do: entity

  defp movement_mode(opts, flags) when (flags &&& 4) != 0, do: Keyword.put(opts, :run?, true)
  defp movement_mode(opts, flags) when (flags &&& 2) != 0, do: Keyword.put(opts, :run?, false)
  defp movement_mode(opts, _flags), do: opts

  defp point_callback(opts, %ScriptStep{datalong4: flags, dataint: point_id}) when (flags &&& 2) != 0 do
    Keyword.put(opts, :movement_inform, %Effects.MovementInform{motion_type: 9, point_id: point_id})
  end

  defp point_callback(opts, %ScriptStep{}), do: opts
end
