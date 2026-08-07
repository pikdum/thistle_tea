defmodule ThistleTea.Game.Player.GossipCondition do
  @moduledoc """
  Explicit gossip-boundary policies over the shared three-valued condition
  evaluator.
  """

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.Context

  require Logger

  def allows?(%Context{}, nil, _policy), do: true

  def allows?(%Context{} = context, %Condition{} = condition, policy) when policy in [:legacy_open, :deny_unknown] do
    case Evaluator.evaluate(context, condition) do
      :met -> true
      :unmet -> false
      {:unknown, reasons} -> handle_unknown(policy, condition, reasons)
    end
  end

  defp handle_unknown(policy, condition, reasons) do
    Logger.debug("Gossip condition #{condition.entry} unresolved under #{policy}: #{inspect(reasons)}")

    policy == :legacy_open
  end
end
