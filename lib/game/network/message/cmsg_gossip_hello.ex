defmodule ThistleTea.Game.Network.Message.CmsgGossipHello do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_HELLO

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem

  require Logger

  defstruct [:guid]

  @creature_guid_offset 0xF1300000

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state) do
    low_guid = guid - @creature_guid_offset

    # TODO: what to do if there are multiple gossip menus?
    # send a packet for each?
    # check conditions?
    case from(c in Mangos.Creature,
           where: c.guid == ^low_guid,
           join: ct in assoc(c, :creature_template),
           left_join: gm in assoc(ct, :gossip_menu),
           select: gm,
           limit: 1
         )
         |> Mangos.Repo.one()
         |> Mangos.Repo.preload(:gossip_menu_option) do
      nil ->
        state

      gm ->
        gmo = Map.get(gm, :gossip_menu_option, [])

        gossips =
          Enum.map(gmo, fn o ->
            %GossipItem{
              id: o.id,
              item_icon: o.option_icon,
              coded: o.box_coded,
              message: o.option_text
            }
          end)

        Network.send_packet(%Message.SmsgGossipMessage{
          guid: guid,
          title_text_id: gm.text_id,
          gossips: gossips,
          quests: []
        })

        Map.put(state, :gossip_menu_options, gmo)
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
