defmodule ThistleTea.Game.Player.Movement do
  @moduledoc """
  Translates client movement events into character movement rules.
  """
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_FALL_LAND, :MSG_MOVE_START_SWIM]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Pathfinding

  def accepts_input?(%Character{internal: %Internal{movement_start_time: started}}) when is_integer(started), do: false
  def accepts_input?(%Character{internal: %Internal{logout: :rooted}}), do: false
  def accepts_input?(%Character{} = character), do: not Core.dead?(character) and not ControlMovement.active?(character)
  def accepts_input?(_character), do: true

  def apply_environment(%Character{} = character, opcode, now) do
    character
    |> Falling.update(action(opcode), now)
    |> Breathing.update(
      liquid_surface(character),
      now,
      :rand.uniform(max(character.unit.level || 1, 1)) - 1,
      body_height(character)
    )
  end

  def interrupt_attacks(character, false, _now), do: character
  def interrupt_attacks(character, true, now), do: AutoRepeat.interrupt(character, now)

  def body_height(%Character{} = character), do: ModelGeometry.height(character.unit.display_id)
  def body_height(_entity), do: 2.0

  def liquid_surface(%Character{} = character) do
    {x, y, z, _} = character.movement_block.position
    Pathfinding.query_liquid_surface(character.internal.world.map_id, {x, y, z})
  end

  def publish_changes(%{character: %Character{} = character} = state) do
    state =
      if character.internal.broadcast_update? do
        PlayerServer.maybe_broadcast_update(state)
      else
        %{state | character: EventSink.emit_pending(character)}
      end

    TickScheduler.ensure_scheduled(state)
  end

  def publish_changes(state), do: state

  defp action(@msg_move_fall_land), do: :land
  defp action(@msg_move_start_swim), do: :swim
  defp action(_opcode), do: :move
end
