defmodule ThistleTea.Game.Network.Message.SmsgMoveSetHover do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MOVE_SET_HOVER

  defstruct [:guid, counter: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, counter: counter}) do
    BinaryUtils.pack_guid(guid) <> <<counter::little-size(32)>>
  end
end
