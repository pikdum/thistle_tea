defmodule ThistleTea.Game.Network.Message.MsgMoveKnockBack do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_MOVE_KNOCK_BACK

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock

  defstruct [:guid, :movement_block]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, movement_block: %MovementBlock{} = movement}) do
    BinaryUtils.pack_guid(guid) <>
      MovementBlock.movement_info_to_binary(movement) <>
      <<movement.cos_angle::little-float-size(32), movement.sin_angle::little-float-size(32),
        movement.xy_speed::little-float-size(32), movement.z_speed::little-float-size(32)>>
  end
end
