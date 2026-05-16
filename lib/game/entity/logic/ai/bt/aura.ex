defmodule ThistleTea.Game.Entity.Logic.AI.BT.Aura do
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Time

  def tick_step do
    BT.action(&tick/2)
  end

  def tick(%{unit: %Unit{auras: [_ | _]}} = entity, %Blackboard{} = blackboard) do
    {entity, events} = AuraLogic.tick(entity, Time.now())
    EventSink.emit(entity, events)
    {:failure, entity, blackboard}
  end

  def tick(entity, %Blackboard{} = blackboard), do: {:failure, entity, blackboard}
end
