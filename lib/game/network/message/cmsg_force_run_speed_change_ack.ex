defmodule ThistleTea.Game.Network.Message.CmsgForceRunSpeedChangeAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FORCE_RUN_SPEED_CHANGE_ACK

  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Session

  defstruct [:guid, :counter, :new_speed]

  @impl ClientMessage
  def handle(
        %__MODULE__{guid: guid, counter: counter, new_speed: new_speed},
        %Session{character: %Character{movement_block: %MovementBlock{} = movement_block} = character} = state
      ) do
    case MovementControl.acknowledge(state, guid, counter, {:run_speed, new_speed}) do
      {:ok, state} ->
        movement_block = %{movement_block | run_speed: new_speed}

        MovementControl.maybe_finish_repop(%{state | character: %{character | movement_block: movement_block}})

      {:error, state} ->
        state
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), counter::little-size(32), rest::binary>> = payload
    info_size = byte_size(rest) - 4
    <<_info::binary-size(^info_size), new_speed::little-float-size(32)>> = rest

    %__MODULE__{
      guid: guid,
      counter: counter,
      new_speed: new_speed
    }
  end
end
