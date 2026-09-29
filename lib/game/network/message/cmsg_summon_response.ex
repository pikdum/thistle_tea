defmodule ThistleTea.Game.Network.Message.CmsgSummonResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SUMMON_RESPONSE

  defstruct [:summoner_guid]

  @impl ClientMessage
  def from_binary(<<summoner_guid::little-size(64)>>) do
    %__MODULE__{summoner_guid: summoner_guid}
  end
end
