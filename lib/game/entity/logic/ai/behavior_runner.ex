defmodule ThistleTea.Game.Entity.Logic.AI.BehaviorRunner do
  @moduledoc """
  Runs due entity maintenance before evaluating an entity's behavior tree.

  Aura and regeneration transitions are runtime upkeep rather than behavioral
  choices, so every entity owner gets the same ordering without embedding
  them in each tree.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT

  def tick(tree, %{internal: %Internal{} = internal} = entity, %Context{now: now} = context) do
    blackboard = Blackboard.from_any(internal.blackboard)
    {:failure, entity, blackboard} = AuraBT.tick(entity, blackboard, now)
    {:failure, entity, blackboard} = RegenBT.tick(entity, blackboard, now)
    entity = %{entity | internal: %{entity.internal | blackboard: blackboard}}
    BT.tick(tree, entity, context)
  end
end
