defmodule ThistleTea.Game.Entity.Logic.AI.BT.Confusion do
  @moduledoc """
  Wanders confused entities around their application point, using only the
  owner's navigation observations and bounded walking paths.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Confusion, as: Memory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math

  @radius 4.0

  def request(%{unit: %Unit{}, internal: %Internal{}} = entity, now) do
    if ControlMovement.mode(entity) == :confusion and not blocked?(entity), do: ready_request(entity, now)
  end

  def request(_entity, _now), do: nil

  defp ready_request(entity, now) do
    memory = memory(entity, Blackboard.ensure(entity.internal.blackboard), now)

    if not Movement.moving?(entity, now) and not memory.moving? and now >= memory.next_move_at do
      {entity.internal.world.map_id, memory.anchor, @radius}
    end
  end

  def tick(%{unit: %Unit{}, internal: %Internal{}} = entity, %Blackboard{} = blackboard, %Context{} = context) do
    if ControlMovement.mode(entity) == :confusion do
      run(entity, %{blackboard | confusion: memory(entity, blackboard, context.now)}, context)
    else
      {:failure, entity, blackboard}
    end
  end

  def tick(entity, blackboard, _context), do: {:failure, entity, blackboard}

  defp run(entity, %Blackboard{confusion: memory} = blackboard, %Context{now: now} = context) do
    cond do
      blocked?(entity) -> {BT.running(500, :confusion), entity, blackboard}
      Movement.moving?(entity, now) -> Navigation.wait_for_arrival(entity, blackboard, context)
      memory.moving? -> pause(entity, blackboard, context)
      now < memory.next_move_at -> {BT.running(memory.next_move_at - now, :confusion), entity, blackboard}
      true -> move(entity, blackboard, context)
    end
  end

  defp move(entity, %Blackboard{confusion: memory} = blackboard, context) do
    case Navigation.wander_point(entity, memory.anchor, @radius, context) do
      nil ->
        pause(entity, blackboard, context)

      destination ->
        destination = bound_destination(destination, memory.anchor)
        entity = %{entity | internal: %{entity.internal | running: false}}
        opts = [run?: false, allow_steep: false, max_distance: 8.0, within_radius: {memory.anchor, @radius}]
        entity = Navigation.move_to(entity, destination, opts, context)
        {BT.running(0, :navigation), entity, %{blackboard | confusion: %{memory | moving?: true}}}
    end
  end

  defp bound_destination({x, y, z} = destination, {ax, ay, az} = anchor) do
    distance = Math.distance(anchor, destination)

    if distance > @radius do
      fraction = @radius / distance
      {ax + (x - ax) * fraction, ay + (y - ay) * fraction, az + (z - az) * fraction}
    else
      destination
    end
  end

  defp pause(entity, %Blackboard{confusion: memory} = blackboard, %Context{now: now, random: random}) do
    delay = Random.between(random, 500, 1_500)
    memory = %{memory | moving?: false, next_move_at: now + delay}
    {BT.running(delay, :confusion), entity, %{blackboard | confusion: memory}}
  end

  defp blocked?(%{unit: unit, internal: internal}) do
    internal.rooted? or Enum.any?(unit.auras, &Holder.has_any_type?(&1, [:mod_root, :mod_stun]))
  end

  defp memory(_entity, %Blackboard{confusion: %Memory{} = memory}, _now), do: memory

  defp memory(entity, _blackboard, now) do
    {x, y, z, _} = entity.movement_block.position
    %Memory{anchor: {x, y, z}, next_move_at: now, previous_running: entity.internal.running}
  end
end
