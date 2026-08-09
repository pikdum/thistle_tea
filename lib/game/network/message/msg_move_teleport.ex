defmodule ThistleTea.Game.Network.Message.MsgMoveTeleport do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_MOVE_TELEPORT

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock

  @enforce_keys [:guid, :movement_block]
  defstruct [:guid, :movement_block]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, movement_block: %MovementBlock{} = movement_block}) do
    BinaryUtils.pack_guid(guid) <> MovementBlock.movement_info_to_binary(movement_block)
  end
end
