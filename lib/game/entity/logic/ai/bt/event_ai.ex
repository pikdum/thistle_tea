defmodule ThistleTea.Game.Entity.Logic.AI.BT.EventAI do
  @moduledoc "Runs eligible creature events before continuing the current behavior tree."

  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.EventAI

  def tick(state, blackboard, %Context{now: now} = context) do
    {state, blackboard} = EventAI.tick(state, blackboard, now, context)
    {:failure, state, blackboard}
  end
end
