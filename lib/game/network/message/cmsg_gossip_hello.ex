defmodule ThistleTea.Game.Network.Message.CmsgGossipHello do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_HELLO

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.QuestItem
  alias ThistleTea.Game.Player.Quests

  require Logger

  @default_gossip_text_id 68

  defstruct [:guid]

  def quest_items(npc_guid, character) do
    {giver_quests, ender_quests} = Quests.npc_quests(npc_guid)

    giver_quests
    |> QuestDialogStatus.menu(ender_quests, Quests.ctx(character))
    |> Enum.map(fn {%Quest{} = quest, icon} ->
      %QuestItem{
        quest_id: quest.id,
        quest_icon: icon,
        level: quest.level,
        title: quest.title
      }
    end)
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{character: %Character{} = c} = state) do
    low_guid = Guid.low_guid(guid)
    quests = quest_items(guid, c)

    # TODO: what to do if there are multiple gossip menus?
    # send a packet for each?
    # check conditions?
    from(c in Mangos.Creature,
      where: c.guid == ^low_guid,
      join: ct in assoc(c, :creature_template),
      left_join: gm in assoc(ct, :gossip_menu),
      select: gm,
      limit: 1
    )
    |> Mangos.Repo.one()
    |> Mangos.Repo.preload(:gossip_menu_option)
    |> case do
      nil ->
        if quests == [] do
          state
        else
          Network.send_packet(%Message.SmsgGossipMessage{
            guid: guid,
            title_text_id: @default_gossip_text_id,
            gossips: [],
            quests: quests
          })

          Map.put(state, :gossip_menu_options, [])
        end

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
          quests: quests
        })

        Map.put(state, :gossip_menu_options, gmo)
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
