defmodule ThistleTea.Game.Network.Message.SmsgPetitionQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PETITION_QUERY_RESPONSE

  alias ThistleTea.Game.Core.Guild.Petitions.Petition

  defstruct [:petition]

  @impl ServerMessage
  def to_binary(%__MODULE__{petition: %Petition{} = petition}) do
    <<petition.id::little-size(32), petition.owner.guid::little-size(64)>> <>
      petition.name <>
      <<0, 0, 1::little-size(32), 9::little-size(32), 9::little-size(32), 0::little-size(32), 0::little-size(32),
        0::little-size(32), 0::little-size(32), 0::little-size(32), 0::little-size(16), 0::little-size(32),
        0::little-size(32), 0::little-size(32), 0::little-size(32)>>
  end
end
