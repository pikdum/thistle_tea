defmodule ThistleTea.Game.Network.Message.SmsgReadItemFailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_READ_ITEM_FAILED

  defstruct [:guid, reason: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, reason: reason}) do
    <<guid::little-size(64), reason::size(8), guid::little-size(64)>>
  end
end
