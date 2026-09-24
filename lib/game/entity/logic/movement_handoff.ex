defmodule ThistleTea.Game.Entity.Logic.MovementHandoff do
  @moduledoc "A one-use final movement snapshot from the client relinquishing a unit."

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Core

  @enforce_keys [:controller_guid, :world, :position, :expires_at]
  defstruct [:controller_guid, :world, :position, :expires_at]

  @timeout_ms 4_000

  def offer(%{internal: %Internal{} = internal, movement_block: %MovementBlock{position: position}} = entity, guid, now)
      when is_integer(guid) and guid > 0 and is_tuple(position) do
    handoff = %__MODULE__{
      controller_guid: guid,
      world: internal.world,
      position: position,
      expires_at: now + @timeout_ms
    }

    %{entity | internal: %{internal | movement_handoff: handoff}}
  end

  def offer(entity, _guid, _now), do: entity

  def clear(%{internal: %Internal{} = internal} = entity), do: %{entity | internal: %{internal | movement_handoff: nil}}
  def clear(entity), do: entity

  def take(%{internal: %Internal{movement_handoff: %__MODULE__{controller_guid: guid} = handoff}} = entity, guid, now) do
    entity = clear(entity)

    if valid?(entity, handoff, now), do: {:ok, entity}, else: {:error, entity}
  end

  def take(entity, _guid, _now), do: {:error, entity}

  defp valid?(entity, handoff, now) do
    now < handoff.expires_at and entity.internal.world == handoff.world and
      entity.movement_block.position == handoff.position and
      is_nil(entity.internal.movement_start_time) and not Core.dead?(entity)
  end
end
