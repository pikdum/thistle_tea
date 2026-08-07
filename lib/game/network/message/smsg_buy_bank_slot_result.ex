defmodule ThistleTea.Game.Network.Message.SmsgBuyBankSlotResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BUY_BANK_SLOT_RESULT

  defstruct [:result]

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}), do: <<result::little-size(32)>>
end
