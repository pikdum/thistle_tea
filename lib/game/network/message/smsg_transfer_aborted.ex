defmodule ThistleTea.Game.Network.Message.SmsgTransferAborted do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TRANSFER_ABORTED

  defstruct [:reason]

  @impl ServerMessage
  def to_binary(%__MODULE__{reason: reason}), do: <<code(reason)>>

  defp code(:instance_full), do: 1
  defp code(:too_many_instances), do: 3
  defp code(:zone_in_combat), do: 5
  defp code(_reason), do: 2
end
