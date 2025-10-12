defmodule ThistleTea.Game.Gossip do
  import Ecto.Query
  import ThistleTea.Util, only: [send_packet: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.Repo

  require Logger

  @creature_guid_offset 0xF1300000

  @cmsg_gossip_hello 0x17B
  @cmsg_gossip_select_option 0x17C
  @cmsg_npc_text_query 0x17F

  @smsg_gossip_message 0x17D
  @smsg_npc_text_update 0x180

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

  defp encode_gossip_options(gmo) do
    gmo
    |> Enum.map(fn o ->
      <<
        # TODO: should this be loop index instead?
        o.id::little-size(32),
        o.option_icon::little-size(8),
        o.box_coded::little-size(8)
      >> <> o.option_text <> <<0>>
    end)
    |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)
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
        gossip_items = encode_gossip_options(gmo)

        packet =
          <<
            guid::little-size(64),
            # title_text_id
            gm.text_id::little-size(32),
            # amount of gossip items
            Enum.count(gmo)::little-size(32)
          >> <>
            gossip_items

        send_packet(@smsg_gossip_message, packet)
        {:continue, state |> Map.put(:gossip_menu_options, gmo)}
    end
  end

  def handle_packet(@cmsg_npc_text_query, <<text_id::little-size(32), _guid::little-size(64)>>, state) do
    case Repo.get(Mangos.NpcText, text_id) do
      nil ->
        {:continue, state}

      npc_text ->
        header = <<text_id::little-size(32)>>

        body =
          text_groups(npc_text)
          |> Enum.map(fn t ->
            <<t.prob::little-float-size(32)>> <>
              if Map.get(t, :text_0) do
                t.text_0 <> <<0>>
              else
                <<0>>
              end <>
              if Map.get(t, :text_1) do
                t.text_1 <> <<0>>
              else
                <<0>>
              end <>
              <<
                # TODO: universal language
                0::little-size(32)
              >> <>
              <<
                # emote blocks
                t.em_0_delay::little-size(32),
                t.em_0::little-size(32),
                t.em_1_delay::little-size(32),
                t.em_1::little-size(32),
                t.em_2_delay::little-size(32),
                t.em_2::little-size(32)
              >>
          end)
          |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)

        send_packet(@smsg_npc_text_update, header <> body)
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
            gossip_items = encode_gossip_options(gmo)

            packet =
              <<
                guid::little-size(64),
                # title_text_id
                gm.text_id::little-size(32),
                # amount of gossip items
                Enum.count(gmo)::little-size(32)
              >> <>
                gossip_items

            send_packet(@smsg_gossip_message, packet)
            {:continue, state |> Map.put(:gossip_menu_options, gmo)}
        end
    end
  end
end
