defmodule ThistleTea.Game.Entity.EventSink.ScriptedEvents do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.System.ScriptedEvent, as: ScriptedEventSystem

  def emit(entity, %Effects.ScriptedEventCommand{} = effect, _context) do
    ScriptedEventSystem.command(effect)
    entity
  end

  def emit(
        entity,
        %Effects.SendScriptEvent{owner_guid: owner_guid, invoker_guid: invoker_guid, event_id: event_id, data: data},
        _context
      ) do
    Entity.script_event(owner_guid, event_id, data, invoker_guid)
    entity
  end
end
