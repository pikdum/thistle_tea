defmodule ThistleTea.Game.Network.Message.CmsgGameobjectQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GAMEOBJECT_QUERY

  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader

  require Logger

  defstruct [:entry, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{entry: entry, guid: guid}, state) do
    case GameObjectTemplateLoader.get(entry) do
      %GameObjectTemplate{} = template ->
        Logger.info("CMSG_GAMEOBJECT_QUERY: #{entry} - #{guid}",
          target_name: template.name
        )

        Network.send_packet(%Message.SmsgGameobjectQueryResponse{
          entry_id: template.entry,
          info_type: template.type,
          display_id: template.display_id,
          name1: template.name,
          name2: "",
          name3: "",
          name4: "",
          name5: "",
          raw_data: template.data
        })

      _ ->
        Network.send_packet(%Message.SmsgGameobjectQueryResponse{entry_id: entry, info_type: nil})
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<entry::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      entry: entry,
      guid: guid
    }
  end
end
