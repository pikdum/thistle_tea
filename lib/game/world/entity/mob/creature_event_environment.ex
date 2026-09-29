defmodule ThistleTea.Game.World.Entity.Mob.CreatureEventEnvironment do
  @moduledoc "Supplies cached world-event data and subscribes each creature owner to relevant changes."

  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.Creature.CreatureEvent
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.GameEvent.CreatureData
  alias ThistleTea.Game.World.Loader.CreatureEvent, as: CreatureEventLoader
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.Topics

  def initialize(%Mob{} = mob, now) do
    for data <- definitions(mob), do: Topics.subscribe(Topics.creature_event(data.event))
    reconcile(mob, now)
  end

  def reconcile(%Mob{} = mob, now) do
    data = CreatureData.select(definitions(mob), GameEvent.active_events())
    random = %Random{float: &:rand.uniform/0, integer: &:rand.uniform/1}
    CreatureEvent.reconcile(mob, data, now, random)
  end

  defp definitions(%Mob{internal: %{creature: %{db_guid: guid}}}), do: CreatureEventLoader.get(guid)
  defp definitions(%Mob{}), do: []
end
