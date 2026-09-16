defmodule ThistleTea.Game.Player.Movement do
  @moduledoc """
  Translates client movement events into character movement rules.
  """
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_FALL_LAND, :MSG_MOVE_START_SWIM]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer

  def apply_fall(%Character{} = character, opcode, now) do
    Falling.update(character, action(opcode), now)
  end

  def publish_changes(%{character: %Character{internal: %{broadcast_update?: true}}} = state) do
    PlayerServer.maybe_broadcast_update(state)
  end

  def publish_changes(state), do: state

  defp action(@msg_move_fall_land), do: :land
  defp action(@msg_move_start_swim), do: :swim
  defp action(_opcode), do: :move
end
