defmodule ThistleTea.Game.Network.Message.SmsgClientControlUpdate do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CLIENT_CONTROL_UPDATE

  alias ThistleTea.Game.Network.BinaryUtils

  defstruct [:guid, allow_movement?: false]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, allow_movement?: allow_movement?}) do
    BinaryUtils.pack_guid(guid) <> <<if(allow_movement?, do: 1, else: 0)::little-size(8)>>
  end
end
