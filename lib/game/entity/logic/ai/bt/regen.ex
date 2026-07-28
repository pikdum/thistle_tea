defmodule ThistleTea.Game.Entity.Logic.AI.BT.Regen do
  @moduledoc """
  Behavior-tree step that runs resource regeneration ticks while the entity
  still needs them.
  """
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Regen, as: RegenLogic

  def tick_step do
    BT.action(&tick_with_context/3)
  end

  def tick(entity, %Blackboard{} = blackboard, now) when is_integer(now) do
    {entity, blackboard} = tick_resources(entity, blackboard, now)
    {entity, blackboard} = tick_focus(entity, blackboard, now)
    {:failure, entity, blackboard}
  end

  defp tick_with_context(entity, %Blackboard{} = blackboard, %Context{now: now}) do
    tick(entity, blackboard, now)
  end

  defp tick_resources(entity, blackboard, now) do
    if Blackboard.ready_for?(blackboard, :next_regen_at, now) do
      entity = if RegenLogic.needs_resource_regen?(entity), do: RegenLogic.tick(entity, now), else: entity
      blackboard = Blackboard.put_next_at(blackboard, :next_regen_at, RegenLogic.tick_ms(entity), now)
      {entity, blackboard}
    else
      {entity, blackboard}
    end
  end

  defp tick_focus(entity, blackboard, now) do
    case RegenLogic.focus_tick_ms(entity) do
      tick_ms when is_integer(tick_ms) ->
        tick_focus(entity, blackboard, now, tick_ms)

      _unsupported ->
        {entity, blackboard}
    end
  end

  defp tick_focus(entity, blackboard, now, tick_ms) do
    if Blackboard.ready_for?(blackboard, :next_focus_regen_at, now) do
      entity = if RegenLogic.needs_focus_regen?(entity), do: RegenLogic.tick_focus(entity), else: entity
      blackboard = Blackboard.put_next_at(blackboard, :next_focus_regen_at, tick_ms, now)
      {entity, blackboard}
    else
      {entity, blackboard}
    end
  end
end
