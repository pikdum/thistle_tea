defmodule ThistleTea.Game.Inbound.CmsgAutostoreBankItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AUTOSTORE_BANK_ITEM

  alias ThistleTea.Game.World.Entity.Player.Bank

  defstruct [:source_bag, :source_slot]

  @impl ClientMessage
  def from_binary(<<source_bag, source_slot>>) do
    %__MODULE__{source_bag: source_bag, source_slot: source_slot}
  end

  @impl ClientMessage
  def handle(%__MODULE__{source_bag: bag, source_slot: slot}, state), do: Bank.auto_store_bank(state, {bag, slot})
end
