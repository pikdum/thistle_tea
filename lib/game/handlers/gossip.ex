defmodule ThistleTea.Game.Gossip do
  use ThistleTea.Opcodes, [
    :CMSG_GOSSIP_HELLO,
    :CMSG_GOSSIP_SELECT_OPTION,
    :CMSG_NPC_TEXT_QUERY,
    :SMSG_GOSSIP_MESSAGE,
    :SMSG_NPC_TEXT_UPDATE
  ]

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgGossipMessage.GossipItem
  alias ThistleTea.Game.Message.SmsgNpcTextUpdate.NpcTextUpdate
  alias ThistleTea.Game.Message.SmsgNpcTextUpdate.NpcTextUpdateEmote
  alias ThistleTea.Util

  require Logger

  @creature_guid_offset 0xF1300000

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

  def handle_packet(@cmsg_gossip_hello, <<guid::little-size(64)>>, state) do
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
        {:continue, state}

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

        Util.send_packet(%Message.SmsgGossipMessage{
          guid: guid,
          title_text_id: gm.text_id,
          gossips: gossips,
          quests: []
        })

        {:continue, state |> Map.put(:gossip_menu_options, gmo)}
    end
  end

  def handle_packet(@cmsg_npc_text_query, <<text_id::little-size(32), _guid::little-size(64)>>, state) do
    case Repo.get(Mangos.NpcText, text_id) do
      nil ->
        {:continue, state}

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

        {:continue, state}
    end
  end

  def handle_packet(@cmsg_gossip_select_option, body, state) do
    <<guid::little-size(64), gossip_list_id::little-size(32), _rest::binary>> = body

    state
    |> Map.get(:gossip_menu_options, [])
    |> Enum.find(fn o -> o.id == gossip_list_id end)
    |> case do
      nil ->
        {:continue, state}

      option ->
        case from(gm in Mangos.GossipMenu, where: gm.entry == ^option.action_menu_id, limit: 1)
             |> Mangos.Repo.one()
             |> Mangos.Repo.preload(:gossip_menu_option) do
          nil ->
            {:continue, state}

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

            Util.send_packet(%Message.SmsgGossipMessage{
              guid: guid,
              title_text_id: gm.text_id,
              gossips: gossips,
              quests: []
            })

            {:continue, state |> Map.put(:gossip_menu_options, gmo)}
        end
    end
  end
end
