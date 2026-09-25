defmodule ThistleTea.Game.Entity.Server.CreatureEventEnvironment do
  @moduledoc "Supplies cached world-event data and subscribes each creature owner to relevant changes."

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.CreatureEvent
  alias ThistleTea.Game.GameEvent.CreatureData
  alias ThistleTea.Game.World.Loader.CreatureEvent, as: CreatureEventLoader
  alias ThistleTea.Game.World.System.GameEvent

  def initialize(%Mob{} = mob, now) do
    for data <- definitions(mob), do: Phoenix.PubSub.subscribe(ThistleTea.PubSub, "creature_event:#{data.event}")
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
