defmodule ThistleTea.Game.Core.Pet.TemporarySummon do
  @moduledoc """
  Timed creature death through the normal death transition. Wild summons defer
  expiry during combat; stationary decoys expire even while under attack.
  """

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Mob

  def tick(%Mob{internal: %{spawn: %Spawn{death_at: deadline} = spawn}} = entity, now)
      when is_integer(deadline) and deadline <= now do
    if spawn.death_in_combat? or entity.internal.in_combat != true, do: Entity.kill(entity, now), else: entity
  end

  def tick(entity, _now), do: entity

  def next_at(%Mob{unit: %{health: health}, internal: %{spawn: %Spawn{death_at: deadline}}}, now)
      when health > 0 and is_integer(deadline), do: max(deadline, now + 100)

  def next_at(_entity, _now), do: nil
end
