defmodule ThistleTea.Game.Message.SmsgGossipMessage do
  use ThistleTea.Game.ServerMessage, :SMSG_GOSSIP_MESSAGE

  defstruct [
    :guid,
    :title_text_id,
    :gossips,
    :quests
  ]

  defmodule GossipItem do
    defstruct [
      :id,
      :item_icon,
      :coded,
      :message
    ]
  end

  defmodule QuestItem do
    defstruct [
      :quest_id,
      :quest_icon,
      :level,
      :title
    ]
  end

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, title_text_id: title_text_id, gossips: gossips, quests: quests}) do
    gossip_data =
      gossips
      |> Enum.map(fn %GossipItem{id: id, item_icon: item_icon, coded: coded, message: message} ->
        <<
          id::little-size(32),
          item_icon::little-size(8),
          coded::little-size(8)
        >> <> message <> <<0>>
      end)
      |> Enum.reduce(<<>>, fn item, acc -> acc <> item end)

    quest_data =
      quests
      |> Enum.map(fn %QuestItem{quest_id: quest_id, quest_icon: quest_icon, level: level, title: title} ->
        <<
          quest_id::little-size(32),
          quest_icon::little-size(32),
          level::little-size(32)
        >> <> title <> <<0>>
      end)
      |> Enum.reduce(<<>>, fn item, acc -> acc <> item end)

    <<
      guid::little-size(64),
      title_text_id::little-size(32),
      length(gossips)::little-size(32)
    >> <>
      gossip_data <>
      <<length(quests)::little-size(32)>> <>
      quest_data
  end
end
