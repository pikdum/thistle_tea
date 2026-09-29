defmodule ThistleTea.Game.Core.AI.BehaviorRunner do
  @moduledoc """
  Runs due entity maintenance before evaluating an entity's behavior tree.

  Aura and regeneration transitions are runtime upkeep rather than behavioral
  choices, so every entity owner gets the same ordering without embedding
  them in each tree.
  """

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Distancing
  alias ThistleTea.Game.Core.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Core.AI.BT.SeekAssistance
  alias ThistleTea.Game.Core.AI.BT.Totem, as: TotemBT
  alias ThistleTea.Game.Core.Combat.CombatLeash
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Combat.UnreachableTarget
  alias ThistleTea.Game.Core.Combat.ZoneCombat
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Environment.LiquidSpells
  alias ThistleTea.Game.Core.Movement.Charge
  alias ThistleTea.Game.Core.Pet.TemporarySummon

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

  defp tick_entity(tree, entity, context) do
    entity = maintain(entity, context)

    if Charge.active?(entity, context.now),
      do: {BT.running(max(entity.internal.charge.arrives_at - context.now, 1), :charge), entity},
      else: BT.tick(tree, entity, context)
  end

  defp maintain(entity, %Context{now: now} = context) do
    entity = LiquidSpells.reconcile(entity, context.liquid_spell, now)
    blackboard = Blackboard.ensure(entity.internal.blackboard)
    {:failure, entity, blackboard} = AuraBT.tick(entity, blackboard, context)
    entity = Engagement.maintain(entity, context)
    {entity, blackboard} = PlayerCombat.sync(entity, blackboard, context)
    {:failure, entity, blackboard} = RegenBT.tick(entity, blackboard, now)
    entity = %{entity | internal: %{entity.internal | blackboard: blackboard}}

    entity
    |> Charge.reconcile(now)
    |> SeekAssistance.maintain(context)
    |> Distancing.maintain(context)
    |> CombatLeash.maintain(now)
    |> UnreachableTarget.maintain(context)
    |> ZoneCombat.maintain(context)
  end
end
