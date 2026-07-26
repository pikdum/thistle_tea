defmodule ThistleTea.Game.Entity.Logic.AI.BT.Aura do
  @moduledoc """
  Behavior-tree step that expires due auras and schedules periodic aura ticks
  while the entity has any auras active.
  """
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Effects

  def tick_step do
    BT.action(&tick_with_context/3)
  end

  def tick(%{unit: %Unit{auras: [_ | _]}} = entity, %Blackboard{} = blackboard, now) when is_integer(now) do
    {entity, events} = AuraLogic.tick(entity, now)
    {:failure, Effects.enqueue(entity, events), blackboard}
  end

  def tick(entity, %Blackboard{} = blackboard, _now), do: {:failure, entity, blackboard}

  defp tick_with_context(entity, %Blackboard{} = blackboard, %Context{now: now}) do
    tick(entity, blackboard, now)
  end
end
