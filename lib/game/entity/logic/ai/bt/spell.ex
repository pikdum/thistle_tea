defmodule ThistleTea.Game.Entity.Logic.AI.BT.Spell do
  @moduledoc """
  Behavior-tree scheduler for in-progress spell casts.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time

  def casting_sequence do
    BT.sequence([
      BT.condition(&casting?/2),
      BT.action(&cast_tick/2)
    ])
  end

  def casting?(%{internal: %Internal{casting: %Cast{}}}, _blackboard), do: true
  def casting?(_entity, _blackboard), do: false

  def cast_tick(entity, %Blackboard{} = blackboard) do
    cast_tick(entity, blackboard, Time.now())
  end

  def cast_tick(entity, blackboard), do: {:failure, entity, blackboard}

  def cast_tick(entity, %Blackboard{} = blackboard, now) when is_integer(now) do
    case Casting.advance(entity, now) do
      {:waiting, entity, delay_ms} -> {{:running, delay_ms}, entity, blackboard}
      {:finished, entity} -> {:success, entity, blackboard}
      {:idle, entity} -> {:failure, entity, blackboard}
    end
  end

  def cast_tick(entity, blackboard, _now), do: {:failure, entity, blackboard}
end
