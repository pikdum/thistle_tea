defmodule ThistleTea.Game.Inbound.CmsgSummonResponse do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SUMMON_RESPONSE

  alias ThistleTea.Game.World.Entity.Player.Summoning

  defstruct [:summoner_guid]

  @impl ClientMessage
  def from_binary(<<summoner_guid::little-size(64)>>) do
    %__MODULE__{summoner_guid: summoner_guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{summoner_guid: summoner_guid}, state) do
    Summoning.accept(state, summoner_guid)
  end
end
