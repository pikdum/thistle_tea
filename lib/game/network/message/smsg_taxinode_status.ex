defmodule ThistleTea.Game.Network.Message.SmsgTaxinodeStatus do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TAXINODE_STATUS

  defstruct [:guid, :known?]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, known?: known?}) do
    <<guid::little-size(64), bool(known?)::little-size(8)>>
  end

  defp bool(true), do: 1
  defp bool(_other), do: 0
end
