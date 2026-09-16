defmodule ThistleTea.Game.Network.Message.CmsgForceRunBackSpeedChangeAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FORCE_RUN_BACK_SPEED_CHANGE_ACK

  alias ThistleTea.Game.Network.MovementControl

  defstruct [:guid, :counter, :new_speed]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, counter: counter, new_speed: speed}, state) do
    MovementControl.acknowledge_speed(state, guid, counter, :run_back_speed, speed)
  end

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), rest::binary>>) do
    info_size = byte_size(rest) - 4
    <<_info::binary-size(^info_size), new_speed::little-float-size(32)>> = rest
    %__MODULE__{guid: guid, counter: counter, new_speed: new_speed}
  end
end
