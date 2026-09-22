defmodule ThistleTea.Game.Player.Knockback do
  @moduledoc """
  Accepts only acknowledgements of issued launches before reconciling movement
  and projecting the acknowledged impulse to nearby observers.
  """
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_KNOCK_BACK]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Player.Movement

  def acknowledge(%State{} = state, guid, counter, payload) do
    movement = MovementBlock.from_binary(payload)

    case MovementControl.acknowledge_knockback(state, guid, counter, movement) do
      {:ok, state} ->
        state
        |> apply_movement(guid, payload)
        |> MovementControl.maybe_finish_repop()

      {:error, state} ->
        state
    end
  end

  defp apply_movement(%State{guid: guid, active_mover_guid: mover, character: %Character{}} = state, guid, payload)
       when mover in [nil, guid] do
    state = %{state | character: Falling.reset(state.character)}
    Movement.handle(%Message.MsgMove{opcode: @msg_move_knock_back, payload: payload}, state)
  end

  defp apply_movement(%State{active_mover_guid: guid} = state, guid, payload) do
    if Companion.control_guid(state.character) == guid do
      Movement.handle(%Message.MsgMove{opcode: @msg_move_knock_back, payload: payload}, state)
    else
      state
    end
  end

  defp apply_movement(state, _guid, _payload), do: state
end
