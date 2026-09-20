defmodule ThistleTea.Game.Network.Message.SmsgPvpCredit do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PVP_CREDIT

  defstruct [:honor, victim_guid: 0, victim_rank: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.honor::little-signed-size(32), message.victim_guid::little-size(64),
      message.victim_rank::little-size(32)>>
  end
end
