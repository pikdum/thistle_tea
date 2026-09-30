defmodule ThistleTea.Game.Inbound.CmsgForceRunSpeedChangeAck do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_FORCE_RUN_SPEED_CHANGE_ACK, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.MovementControl

  defstruct [:guid, :counter, :new_speed]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), rest::binary>>) do
    info_size = byte_size(rest) - 4
    <<_info::binary-size(^info_size), new_speed::little-float-size(32)>> = rest
    %__MODULE__{guid: guid, counter: counter, new_speed: new_speed}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, counter: counter, new_speed: speed}, state) do
    MovementControl.acknowledge_speed(state, guid, counter, :run_speed, speed)
  end
end
