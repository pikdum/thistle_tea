defmodule ThistleTea.Game.Entity.EventSink.CombatLeashes do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.CombatLeashes

  def emit(%Mob{} = entity, %Effects.CombatLeashEvent{ref: ref, event: event}, %Context{owner_pid: owner}) do
    if event == :stop or ref == CombatLeash.reference(entity), do: CombatLeashes.event(ref, event, owner)
    entity
  end

  def emit(entity, _effect, _context), do: entity
end
