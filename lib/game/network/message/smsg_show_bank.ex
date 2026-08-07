defmodule ThistleTea.Game.Network.Message.SmsgShowBank do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SHOW_BANK

  defstruct [:banker_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{banker_guid: banker_guid}), do: <<banker_guid::little-size(64)>>
end
