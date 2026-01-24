defmodule ThistleTea.Game.Network.Message.CmsgForceRunSpeedChangeAck do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FORCE_RUN_SPEED_CHANGE_ACK

  defstruct [:guid, :counter, :new_speed]

  @impl ClientMessage
  def handle(
        %__MODULE__{new_speed: new_speed},
        %{character: %Character{movement_block: %MovementBlock{} = movement_block} = character} = state
      ) do
    movement_block = %{movement_block | run_speed: new_speed}
    character = %{character | movement_block: movement_block}
    %{state | character: character}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), counter::little-size(32), rest::binary>> = payload
    info_size = byte_size(rest) - 4
    <<_info::binary-size(info_size), new_speed::little-float-size(32)>> = rest

    %__MODULE__{
      guid: guid,
      counter: counter,
      new_speed: new_speed
    }
  end
end
