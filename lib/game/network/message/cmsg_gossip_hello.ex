defmodule ThistleTea.Game.Network.Message.CmsgGossipHello do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_HELLO

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.GossipItem
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage.QuestItem
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu

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

  def send_menu(npc_guid, %Menu{} = menu, quests, %{character: %Character{} = c} = state) do
    options = visible_options(menu.options, npc_guid, c)

    gossips =
      Enum.map(options, fn o ->
        %GossipItem{
          id: o.id,
          item_icon: o.icon,
          coded: o.coded,
          message: o.text
        }
      end)

    Network.send_packet(%Message.SmsgGossipMessage{
      guid: npc_guid,
      title_text_id: menu.text_id,
      gossips: gossips,
      quests: quests
    })

    Map.put(state, :gossip_menu_options, options)
  end

  defp visible_options(options, npc_guid, %Character{unit: unit}) do
    trainer_option_id = GossipLoader.option_trainer()

    Enum.filter(options, fn
      %{option_id: ^trainer_option_id} ->
        GossipLoader.trainer_of?(Guid.entry(npc_guid), unit.class, unit.race)

      _option ->
        true
    end)
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    quests = quest_items(guid, c)

    case GossipLoader.menu_for_creature(Guid.entry(guid)) do
      %Menu{} = menu ->
        send_menu(guid, menu, quests, state)

      nil when quests != [] ->
        send_menu(guid, %Menu{text_id: @default_gossip_text_id, options: []}, quests, state)

      nil ->
        state
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
