defmodule ThistleTea.Game.Entity.EventSink.ScriptedEvents do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.Script.Request
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.ScriptDelivery
  alias ThistleTea.Game.World.System.ScriptedEvent, as: ScriptedEventSystem

  def emit(entity, %Effects.ScriptedEventCommand{reply: nil} = effect, _context) do
    ScriptedEventSystem.command(effect)
    entity
  end

  def emit(entity, %Effects.ScriptedEventCommand{} = effect, context) do
    status =
      case ScriptedEventSystem.command_result(effect) do
        :ok -> :continue
        {:error, _reason} -> if(effect.step.abort_on_failure?, do: :terminated, else: :continue)
      end

    reply(effect.reply, status, context)
    entity
  end

  def emit(entity, %Effects.ScriptReply{request: request, status: status}, _context) do
    ScriptDelivery.reply(request, status)
    entity
  end

  def emit(entity, %Effects.ScriptCompleted{} = effect, context) do
    Context.send(context, effect)
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

  defp reply(%Request{} = request, status, _context), do: ScriptDelivery.reply(request, status)

  defp reply({id, receipt, world}, status, context),
    do: Context.send(context, {:script_resume, id, receipt, world, status})
end
