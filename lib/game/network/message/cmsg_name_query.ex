defmodule ThistleTea.Game.Network.Message.CmsgNameQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_NAME_QUERY

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Metadata

  require Logger

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state) do
    info = name_info(guid)
    Logger.info("CMSG_NAME_QUERY", target_name: info.name)

    Network.send_packet(%Message.SmsgNameQueryResponse{
      guid: guid,
      character_name: info.name,
      realm_name: info.realm,
      race: info.race,
      gender: info.gender,
      class: info.class
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

  defp name_info(guid) do
    case Metadata.query(guid, [:name, :realm, :race, :gender, :class]) do
      %{name: name} = info when is_binary(name) ->
        %{name: name, realm: info.realm || "", race: info.race, gender: info.gender, class: info.class}

      _ ->
        offline_name_info(guid)
    end
  end

  defp offline_name_info(guid) do
    case Character.get_character_by_id(Guid.low_guid(guid)) do
      {:ok, %Character{} = c} ->
        %{name: c.internal.name, realm: "", race: c.unit.race, gender: c.unit.gender, class: c.unit.class}

      _ ->
        %{name: "Unknown", realm: "", race: 0, gender: 0, class: 0}
    end
  end
end
