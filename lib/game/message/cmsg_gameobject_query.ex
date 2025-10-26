defmodule ThistleTea.Game.Message.CmsgGameobjectQuery do
  use ThistleTea.Game.ClientMessage, :CMSG_GAMEOBJECT_QUERY

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

  defstruct [:entry, :guid]

  # prevent collisions
  @game_object_guid_offset 0xF1100000

  @impl ClientMessage
  def handle(%__MODULE__{entry: entry, guid: guid}, state) do
    game_object =
      Mangos.Repo.get(Mangos.GameObject, guid - @game_object_guid_offset)
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

    Util.send_packet(%Message.SmsgGameobjectQueryResponse{
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
