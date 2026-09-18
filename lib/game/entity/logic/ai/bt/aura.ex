defmodule ThistleTea.Game.Entity.Logic.AI.BT.Aura do
  @moduledoc """
  Behavior-tree step that expires due auras and schedules periodic aura ticks
  while the entity has any auras active.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
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
    entity = put_blackboard(entity, blackboard)
    {entity, events} = AuraLogic.tick(entity, now)
    {:failure, Effects.enqueue(entity, events), updated_blackboard(entity, blackboard)}
  end

  def tick(entity, %Blackboard{} = blackboard, _now), do: {:failure, entity, blackboard}

  defp tick_with_context(entity, %Blackboard{} = blackboard, %Context{now: now}) do
    tick(entity, blackboard, now)
  end

  defp put_blackboard(%{internal: %Internal{} = internal} = entity, blackboard) do
    %{entity | internal: %{internal | blackboard: blackboard}}
  end

  defp put_blackboard(entity, _blackboard), do: entity

  defp updated_blackboard(%{internal: %Internal{blackboard: blackboard}}, _previous), do: blackboard
  defp updated_blackboard(_entity, previous), do: previous
end
