defmodule ThistleTea.Game.Core.AI.BT.EventAI do
  @moduledoc "Runs eligible creature events before continuing the current behavior tree."

  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.EventAI

  def tick(state, blackboard, %Context{now: now} = context) do
    {state, blackboard} = EventAI.tick(state, blackboard, now, context)
    {:failure, state, blackboard}
  end

  def enter_combat(state, blackboard, enemy_guid, %Context{now: now} = context) do
    EventAI.enter_combat(state, blackboard, enemy_guid, now, context)
  end
end
