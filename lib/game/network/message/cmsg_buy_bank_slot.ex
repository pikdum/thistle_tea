defmodule ThistleTea.Game.Network.Message.CmsgBuyBankSlot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUY_BANK_SLOT

  defstruct [:banker_guid]

  @impl ClientMessage
  def from_binary(<<banker_guid::little-size(64)>>), do: %__MODULE__{banker_guid: banker_guid}
end
