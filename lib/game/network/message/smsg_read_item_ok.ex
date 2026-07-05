defmodule ThistleTea.Game.Network.Message.SmsgReadItemOk do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_READ_ITEM_OK

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}) do
    <<guid::little-size(64), guid::little-size(64)>>
  end
end
