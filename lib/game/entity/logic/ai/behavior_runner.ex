defmodule ThistleTea.Game.Entity.Logic.AI.BehaviorRunner do
  @moduledoc """
  Runs due entity maintenance before evaluating an entity's behavior tree.

  Aura and regeneration transitions are runtime upkeep rather than behavioral
  choices, so every entity owner gets the same ordering without embedding
  them in each tree.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Totem, as: TotemBT
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.TemporarySummon
  alias ThistleTea.Game.Entity.Logic.UnreachableTarget

  def tick(tree, %{internal: %Internal{}} = entity, %Context{now: now} = context) do
    entity = TemporarySummon.tick(entity, now)
    tick_entity(tree, entity, context)
  end

  defp tick_entity(tree, %Mob{unit: %{health: 0}} = entity, context), do: BT.tick(tree, entity, context)

  defp tick_entity(tree, %Mob{internal: %Internal{totem: %Totem{expires_at: expires_at}}} = entity, context) do
    entity =
      if TotemBT.owner_present?(entity, context) do
        now = if is_integer(expires_at), do: min(context.now, expires_at), else: context.now
        maintain(entity, %{context | now: now})
      else
        entity
      end

    BT.tick(tree, entity, context)
  end

  defp tick_entity(tree, entity, context), do: BT.tick(tree, maintain(entity, context), context)

  defp maintain(entity, %Context{now: now} = context) do
    blackboard = Blackboard.ensure(entity.internal.blackboard)
    {:failure, entity, blackboard} = AuraBT.tick(entity, blackboard, context)
    {:failure, entity, blackboard} = RegenBT.tick(entity, blackboard, now)
    entity = %{entity | internal: %{entity.internal | blackboard: blackboard}}
    entity |> CombatLeash.maintain(now) |> UnreachableTarget.maintain(context)
  end
end
