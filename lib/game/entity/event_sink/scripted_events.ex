defmodule ThistleTea.Game.Entity.EventSink.ScriptedEvents do
  @moduledoc false

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.System.ScriptedEvent, as: ScriptedEventSystem

  def emit(entity, %Effects.ScriptedEventCommand{} = effect, _context) do
    ScriptedEventSystem.command(effect)
    entity
  end
end
