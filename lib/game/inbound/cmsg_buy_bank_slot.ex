defmodule ThistleTea.Game.Inbound.CmsgBuyBankSlot do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BUY_BANK_SLOT

  alias ThistleTea.Game.World.Entity.Player.Bank

  defstruct [:banker_guid]

  @impl ClientMessage
  def from_binary(<<banker_guid::little-size(64)>>), do: %__MODULE__{banker_guid: banker_guid}

  @impl ClientMessage
  def handle(%__MODULE__{banker_guid: banker_guid}, state), do: Bank.buy_slot(state, banker_guid)
end
