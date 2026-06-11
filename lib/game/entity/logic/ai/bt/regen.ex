defmodule ThistleTea.Game.Entity.Logic.AI.BT.Regen do
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Regen, as: RegenLogic
  alias ThistleTea.Game.Time

  def tick_step do
    BT.action(&tick/2)
  end

  def tick(entity, %Blackboard{} = blackboard) do
    tick(entity, blackboard, Time.now())
  end

  def tick(entity, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Blackboard.ready_for?(blackboard, :next_regen_at, now) and RegenLogic.needs_regen?(entity) do
      entity = RegenLogic.tick(entity, now)
      blackboard = Blackboard.put_next_at(blackboard, :next_regen_at, RegenLogic.tick_ms(), now)
      {:failure, entity, blackboard}
    else
      {:failure, entity, blackboard}
    end
  end
end
