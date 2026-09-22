defmodule ThistleTea.Game.Entity.Logic.AI.BT.Passive do
  @moduledoc """
  Stationary creatures that never select victims, chase, evade, or melee.
  Shared runtime upkeep still advances their auras and lifetime.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT

  def tree, do: BT.action(&idle/2)

  defp idle(state, blackboard), do: {BT.running(1_000, :passive), state, blackboard}
end
