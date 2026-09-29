defmodule ThistleTea.Game.Core.Condition.Leaf do
  @moduledoc false

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.Leaf.Player
  alias ThistleTea.Game.Core.Condition.Leaf.Unit
  alias ThistleTea.Game.Core.Condition.Leaf.World

  def evaluate(%Context{} = context, %Condition{} = condition) do
    case Player.evaluate(context, condition) do
      :unhandled -> evaluate_unit(context, condition)
      result -> result
    end
  end

  defp evaluate_unit(context, condition) do
    case Unit.evaluate(context, condition) do
      :unhandled -> World.evaluate(context, condition)
      result -> result
    end
  end
end
