defmodule ThistleTea.Game.World.Entity.Mob.SummonLifecycle do
  @moduledoc """
  Delivers summon lifecycle edges to the creating creature or game object and restores the
  departing summon's observation for data-driven EventAI conditions and targets.
  """

  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Metadata

  def notify(%Mob{internal: %{spawn: %Spawn{summoner_guid: summoner}}} = mob, event)
      when is_integer(summoner) and summoner > 0 do
    if Guid.entity_type(summoner) in [:mob, :pet, :game_object] do
      Entity.summon_event(summoner, %SummonEvent{
        event: event,
        entry: mob.object.entry,
        world: mob.internal.world,
        observation: observation(mob)
      })
    end

    mob
  end

  def notify(%Mob{} = mob, _event), do: mob

  def receive_event(%Mob{internal: %{world: world}} = mob, %SummonEvent{world: world} = event, now) do
    context = AIEnvironment.context(mob, now, Request.actor(event.observation.guid))
    {_, x, y, z} = event.observation.position
    {mx, my, mz, _orientation} = mob.movement_block.position
    observation = %{event.observation | distance: Math.distance({mx, my, mz}, {x, y, z})}
    perception = %{context.perception | entities: Map.put(context.perception.entities, observation.guid, observation)}
    context = %{context | perception: perception}
    EventAI.with_blackboard(mob, &EventAI.on_summon_event(&1, &2, event, context))
  end

  def receive_event(%Mob{} = mob, %SummonEvent{}, _now), do: mob

  defp observation(%Mob{} = mob) do
    {x, y, z, _orientation} = mob.movement_block.position
    position = {mob.internal.world, x, y, z}

    metadata =
      Map.merge(Metadata.get(mob.object.guid) || %{}, %{
        alive?: not EntityCore.dead?(mob),
        in_combat: mob.internal.in_combat,
        health_pct: EntityCore.health_pct(mob),
        mana_pct: EntityCore.mana_pct(mob),
        aura_stacks: Aura.spell_stacks(mob),
        aura_effects: Aura.effect_keys(mob)
      })

    %Observation{
      guid: mob.object.guid,
      position: position,
      grounded_position: position,
      metadata: metadata
    }
  end
end
