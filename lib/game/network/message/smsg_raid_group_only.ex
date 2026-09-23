defmodule ThistleTea.Game.Network.Message.SmsgRaidGroupOnly do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_RAID_GROUP_ONLY

  defstruct delay_ms: 0, reason: :required

  @impl ServerMessage
  def to_binary(%__MODULE__{delay_ms: delay, reason: reason}) do
    <<delay::little-size(32), code(reason)::little-size(32)>>
  end

  defp code(:required), do: 1
  defp code(:full), do: 2
end
