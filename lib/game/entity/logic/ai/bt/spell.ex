defmodule ThistleTea.Game.Entity.Logic.AI.BT.Spell do
  @moduledoc """
  Behavior-tree scheduler for in-progress spell casts.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Spell.Cast

  def casting_sequence do
    BT.sequence([
      BT.condition(&casting?/2),
      BT.action(&cast_tick_with_context/3)
    ])
  end

  def casting?(%{internal: %Internal{casting: %Cast{}}}, _blackboard), do: true
  def casting?(_entity, _blackboard), do: false

  def cast_tick(%{internal: %Internal{} = internal} = entity, %Blackboard{} = blackboard, now) when is_integer(now) do
    entity = %{entity | internal: %{internal | blackboard: blackboard}}

    case Casting.advance(entity, now) do
      {:waiting, entity, delay_ms} -> {{:running, delay_ms}, entity, entity.internal.blackboard}
      {:finished, entity} -> {:success, entity, entity.internal.blackboard}
      {:idle, entity} -> {:failure, entity, entity.internal.blackboard}
    end
  end

  def cast_tick(entity, blackboard, _now), do: {:failure, entity, blackboard}

  defp cast_tick_with_context(entity, blackboard, %Context{now: now}) do
    cast_tick(entity, blackboard, now)
  end
end
