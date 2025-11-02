defmodule ThistleTea.Game.Network.Message.CmsgNameQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_NAME_QUERY

  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state) do
    [{^guid, character_name, realm_name, race, gender, class}] = :ets.lookup(:guid_name, guid)

    Logger.info("CMSG_NAME_QUERY", target_name: character_name)

    Network.send_packet(%Message.SmsgNameQueryResponse{
      guid: guid,
      character_name: character_name,
      realm_name: realm_name,
      race: race,
      gender: gender,
      class: class
    })

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
