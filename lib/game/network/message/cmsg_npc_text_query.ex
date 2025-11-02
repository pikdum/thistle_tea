defmodule ThistleTea.Game.Network.Message.CmsgNpcTextQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_NPC_TEXT_QUERY

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdate
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdateEmote
  alias ThistleTea.Util

  require Logger

  defstruct [:text_id, :guid]

  defp text_groups(npc_text) do
    0..7
    |> Enum.reduce([], fn i, acc ->
      text_group = %{
        text_0: Map.get(npc_text, String.to_atom("text#{i}_0")),
        text_1: Map.get(npc_text, String.to_atom("text#{i}_1")),
        lang: Map.get(npc_text, String.to_atom("lang#{i}")),
        prob: Map.get(npc_text, String.to_atom("prob#{i}")),
        em_0_delay: Map.get(npc_text, String.to_atom("em#{i}_0_delay")),
        em_0: Map.get(npc_text, String.to_atom("em#{i}_0")),
        em_1_delay: Map.get(npc_text, String.to_atom("em#{i}_1_delay")),
        em_1: Map.get(npc_text, String.to_atom("em#{i}_1")),
        em_2_delay: Map.get(npc_text, String.to_atom("em#{i}_2_delay")),
        em_2: Map.get(npc_text, String.to_atom("em#{i}_2"))
      }

      [text_group | acc]
    end)
    |> Enum.reverse()
  end

  @impl ClientMessage
  def handle(%__MODULE__{text_id: text_id}, state) do
    case Repo.get(Mangos.NpcText, text_id) do
      nil ->
        state

      npc_text ->
        texts =
          text_groups(npc_text)
          |> Enum.map(fn t ->
            %NpcTextUpdate{
              probability: t.prob,
              texts: [Map.get(t, :text_0), Map.get(t, :text_1)],
              language: 0,
              emotes: [
                %NpcTextUpdateEmote{delay: t.em_0_delay, emote: t.em_0},
                %NpcTextUpdateEmote{delay: t.em_1_delay, emote: t.em_1},
                %NpcTextUpdateEmote{delay: t.em_2_delay, emote: t.em_2}
              ]
            }
          end)

        Util.send_packet(%Message.SmsgNpcTextUpdate{
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
