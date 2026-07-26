defmodule ThistleTea.Game.Entity.Logic.AI.BT.Navigation do
  @moduledoc """
  Shared navigation primitives composed by mob and companion behavior trees.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation, as: PathSource
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Movement

  def target_valid_same_map?(%{internal: %Internal{world: world}}, target_guid, %Context{perception: perception})
      when is_integer(target_guid) do
    case Perception.position(perception, target_guid) do
      {^world, _x, _y, _z} -> true
      _ -> false
    end
  end

  def target_valid_same_map?(_entity, _target_guid, %Context{}), do: false

  def target_alive_same_map?(entity, target_guid, %Context{perception: perception} = context) do
    target_valid_same_map?(entity, target_guid, context) and not dead?(Perception.metadata(perception, target_guid))
  end

  def move_to(entity, destination, opts, %Context{}) do
    NavigationIntent.enqueue(entity, destination, opts)
  end

  def chase(entity, target_guid, destination, %Context{} = context) do
    move_to(entity, destination, [face_target: target_guid], context)
  end

  def follow(entity, destination, orientation, velocity, %Context{} = context) do
    move_to(entity, destination, [face_angle: orientation, velocity: velocity], context)
  end

  def wander_point(%{internal: %Internal{world: world}}, anchor, radius, %Context{navigation: navigation}) do
    PathSource.find_random_point(navigation, world.map_id, anchor, radius)
  end

  def wait_for_arrival(entity, %Blackboard{} = blackboard, %Context{now: now}, wakes \\ []) do
    cond do
      NavigationIntent.pending?(entity) ->
        {BT.running(0, :navigation), entity, blackboard}

      Movement.moving?(entity, now) ->
        movement_delay = Movement.next_spatial_update_delay(entity, now)
        {reason, delay_ms} = soonest_wake([{:movement, movement_delay} | wakes], :movement, movement_delay)
        {BT.running(delay_ms, reason), entity, blackboard}

      true ->
        {:success, entity, Blackboard.clear_move_target(blackboard)}
    end
  end

  defp dead?(%{alive?: false}), do: true
  defp dead?(_metadata), do: false

  defp soonest_wake(wakes, fallback_reason, fallback_delay) do
    wakes
    |> Enum.filter(fn {_reason, delay} -> is_integer(delay) and delay > 0 end)
    |> Enum.min_by(fn {_reason, delay} -> delay end, fn -> {fallback_reason, fallback_delay} end)
  end
end
