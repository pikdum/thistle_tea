defmodule ThistleTea.Game.Entity.EventSink.CombatLeashes do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.CombatLeash.Owner
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CombatLeashes
  alias ThistleTea.Game.World.Metadata

  def emit(%Mob{} = entity, %Effects.CombatLeashEvent{ref: ref, event: {:start, now, source}}, %Context{
        owner_pid: owner
      }) do
    if ref == CombatLeash.reference(entity),
      do: CombatLeashes.event(ref, {:start, now, resolve_source(entity, source)}, owner)

    entity
  end

  def emit(%Mob{} = entity, %Effects.CombatLeashEvent{ref: ref, event: event}, %Context{owner_pid: owner}) do
    CombatLeashes.event(ref, event, owner)
    entity
  end

  def emit(entity, _effect, _context), do: entity

  defp resolve_source(%Mob{internal: %{world: world}}, {:owner, guid, fallback}) do
    with pid when is_pid(pid) <- Entity.pid(guid),
         {^world, _, _, _} <- World.position(guid),
         %{incarnation_id: incarnation} when is_integer(incarnation) <- Metadata.query(guid, [:incarnation_id]) do
      %Owner{world: world, guid: guid, incarnation: incarnation, pid: pid}
    else
      _missing -> fallback
    end
  end

  defp resolve_source(_entity, source), do: source
end
