defmodule ThistleTea.Game.Network.Message.CmsgGossipSelectOption do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_SELECT_OPTION

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem

  require Logger

  defstruct [:guid, :gossip_list_id, :code]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, gossip_list_id: gossip_list_id}, state) do
    state
    |> Map.get(:gossip_menu_options, [])
    |> Enum.find(fn o -> o.id == gossip_list_id end)
    |> case do
      nil ->
        state

      option ->
        case from(gm in Mangos.GossipMenu, where: gm.entry == ^option.action_menu_id, limit: 1)
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
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), gossip_list_id::little-size(32), rest::binary>> = payload

    # TODO: parse code if needed
    %__MODULE__{
      guid: guid,
      gossip_list_id: gossip_list_id,
      code: rest
    }
  end
end
