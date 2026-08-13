defmodule ThistleTea.Game.Network.Message.SmsgGroupJoinedBattleground do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GROUP_JOINED_BATTLEGROUND

  defstruct [:result]

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}), do: <<result::little-size(32)>>
end
