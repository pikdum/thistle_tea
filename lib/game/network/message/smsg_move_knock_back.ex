defmodule ThistleTea.Game.Network.Message.SmsgMoveKnockBack do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MOVE_KNOCK_BACK

  defstruct [:guid, :cos_angle, :sin_angle, :horizontal_speed, :vertical_speed, counter: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    BinaryUtils.pack_guid(message.guid) <>
      <<message.counter::little-size(32), message.cos_angle::little-float-size(32),
        message.sin_angle::little-float-size(32), message.horizontal_speed::little-float-size(32),
        message.vertical_speed::little-float-size(32)>>
  end
end
