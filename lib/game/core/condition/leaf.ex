defmodule ThistleTea.Game.Core.Condition.Leaf do
  @moduledoc """
  Evaluates one leaf condition by asking the player, unit, and world
  evaluators in turn until one handles it.

  The evaluators are called through a variable rather than by name. Naming
  them lets the type checker compose their large multi-clause signatures,
  which took close to four minutes of every compile that re-verified this
  module.
  """

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.Leaf.Player
  alias ThistleTea.Game.Core.Condition.Leaf.Unit
  alias ThistleTea.Game.Core.Condition.Leaf.World

  @evaluators [Player, Unit, World]

  def evaluate(%Context{} = context, %Condition{} = condition) do
    Enum.reduce_while(@evaluators, :unhandled, fn evaluator, :unhandled ->
      case evaluator.evaluate(context, condition) do
        :unhandled -> {:cont, :unhandled}
        result -> {:halt, result}
      end
    end)
  end
end
