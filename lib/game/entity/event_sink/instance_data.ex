defmodule ThistleTea.Game.Entity.EventSink.InstanceData do
  @moduledoc false

  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  require Logger

  def emit(entity, %Effects.InstanceCreatureEvent{} = effect, context) do
    InstanceSystem.creature_event(effect.world, effect, instance_system(context))
    entity
  end

  def emit(entity, %Effects.InstanceDataCommand{} = effect, context) do
    server = instance_system(context)

    try do
      case InstanceSystem.command(effect.world, effect.field, effect.value, effect.mode, server) do
        {:ok, _stored} ->
          entity

        {:error, reason} ->
          log_rejection(effect, reason)
          entity
      end
    catch
      :exit, reason ->
        log_rejection(effect, {:owner_exit, reason})
        entity
    end
  end

  defp instance_system(%Context{instance_system: server}) when not is_nil(server), do: server
  defp instance_system(_context), do: InstanceSystem

  defp log_rejection(effect, reason) do
    Logger.warning(
      "Script #{effect.script_id || 0}: instance data command rejected for #{inspect(effect.world)} field #{effect.field}: #{inspect(reason)}"
    )
  end
end
