defmodule ThistleTea.Game.Entity.EventSink.CreatureGroups do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.CreatureGroups

  def emit(%Mob{} = entity, %Effects.CreatureGroupEvent{event: event}, %Context{owner_pid: owner}) do
    CreatureGroups.event(entity, event, owner)
    entity
  end

  def emit(%Mob{} = entity, %Effects.CreatureGroupCommand{command: :leave}, %Context{owner_pid: owner}) do
    CreatureGroups.leave(entity.internal.world, entity.object.guid, owner)
    entity
  end

  def emit(%Mob{} = entity, %Effects.CreatureGroupCommand{command: {:join, target, member}}, %Context{owner_pid: owner}) do
    CreatureGroups.join(entity.internal.world, entity.object.guid, target, member, owner)
    entity
  end

  def emit(entity, _effect, _context), do: entity
end
