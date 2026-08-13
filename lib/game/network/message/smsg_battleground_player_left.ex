defmodule ThistleTea.Game.Network.Message.SmsgBattlegroundPlayerLeft do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BATTLEGROUND_PLAYER_LEFT

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
