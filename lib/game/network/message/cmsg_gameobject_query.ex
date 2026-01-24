defmodule ThistleTea.Game.Network.Message.CmsgGameobjectQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GAMEOBJECT_QUERY

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct [:entry, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{entry: entry, guid: guid}, state) do
    low_guid = Guid.low_guid(guid)

    game_object =
      Mangos.Repo.get(Mangos.GameObject, low_guid)
      |> Mangos.Repo.preload(:game_object_template)

    template = game_object.game_object_template

    Logger.info("CMSG_GAMEOBJECT_QUERY: #{entry} - #{guid}",
      target_name: template.name
    )

    data = [
      template.data0,
      template.data1,
      template.data2,
      template.data3,
      template.data4,
      template.data5,
      template.data6,
      template.data7,
      template.data8,
      template.data9,
      template.data10,
      template.data11,
      template.data12,
      template.data13,
      template.data14,
      template.data15,
      template.data16,
      template.data17,
      template.data18,
      template.data19,
      template.data20,
      template.data21,
      template.data22,
      template.data23
    ]

    Network.send_packet(%Message.SmsgGameobjectQueryResponse{
      entry_id: template.entry,
      info_type: template.type,
      display_id: template.display_id,
      name1: template.name,
      name2: "",
      name3: "",
      name4: "",
      name5: "",
      raw_data: data
    })

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
