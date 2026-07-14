defmodule ThistleTea.Game.Network.Message.CmsgNpcTextQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_NPC_TEXT_QUERY

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdate
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdateEmote
  alias ThistleTea.Game.World.Loader.NpcText, as: NpcTextLoader

  defstruct [:text_id, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{text_id: text_id}, state) do
    case NpcTextLoader.get(text_id) do
      nil ->
        state

      groups ->
        texts =
          Enum.map(groups, fn t ->
            %NpcTextUpdate{
              probability: t.prob,
              texts: [Map.get(t, :text_0), Map.get(t, :text_1)],
              language: t.lang,
              emotes: [
                %NpcTextUpdateEmote{delay: t.em_0_delay, emote: t.em_0},
                %NpcTextUpdateEmote{delay: t.em_1_delay, emote: t.em_1},
                %NpcTextUpdateEmote{delay: t.em_2_delay, emote: t.em_2}
              ]
            }
          end)

        Network.send_packet(%Message.SmsgNpcTextUpdate{
          text_id: text_id,
          texts: texts
        })

        state
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<text_id::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      text_id: text_id,
      guid: guid
    }
  end
end
