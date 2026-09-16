defmodule ThistleTea.Game.Network.Message.MsgMoveSetSwimBackSpeed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_MOVE_SET_SWIM_BACK_SPEED

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock

  @enforce_keys [:guid, :movement_block, :speed]
  defstruct [:guid, :movement_block, :speed]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, movement_block: %MovementBlock{} = movement, speed: speed}) do
    BinaryUtils.pack_guid(guid) <>
      MovementBlock.movement_info_to_binary(movement) <>
      <<speed::little-float-size(32)>>
  end
end
