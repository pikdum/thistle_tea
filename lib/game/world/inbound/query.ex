defmodule ThistleTea.Game.World.Inbound.Query do
  @moduledoc "Handles decoded cache query client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.CreatureTemplate
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdate
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdateEmote
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.Login
  alias ThistleTea.Game.World.Entity.Player.Pets
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.NpcText, as: NpcTextLoader
  alias ThistleTea.Game.World.Loader.PageText, as: PageTextLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound

  require Logger

  @missing_page_text "Item page missing."

  def messages do
    [
      Message.CmsgCreatureQuery,
      Message.CmsgGameobjectQuery,
      Message.CmsgItemNameQuery,
      Message.CmsgItemQuerySingle,
      Message.CmsgNameQuery,
      Message.CmsgNpcTextQuery,
      Message.CmsgPageTextQuery,
      Message.CmsgPetNameQuery,
      Message.CmsgQueryTime,
      Message.CmsgQuestQuery
    ]
  end

  def handle(%Message.CmsgCreatureQuery{entry: entry, guid: guid}, state) do
    case CreatureTemplateLoader.get(entry) do
      %CreatureTemplate{} = ct ->
        Logger.info("CMSG_CREATURE_QUERY",
          target_name: ct.name
        )

        Outbound.send_packet(%Message.SmsgCreatureQueryResponse{
          creature_entry: entry,
          found: true,
          name1: ct.name,
          name2: "",
          name3: "",
          name4: "",
          sub_name: ct.sub_name,
          type_flags: ct.type_flags,
          creature_type: ct.creature_type,
          creature_family: ct.family,
          creature_rank: ct.rank,
          unknown0: 0,
          spell_data_id: 0,
          display_id: display_id(guid, ct),
          civilian: ct.civilian,
          racial_leader: ct.racial_leader
        })

      _ ->
        Outbound.send_packet(%Message.SmsgCreatureQueryResponse{creature_entry: entry, found: false})
    end

    state
  end

  def handle(%Message.CmsgGameobjectQuery{entry: entry, guid: guid}, state) do
    case GameObjectTemplateLoader.get(entry) do
      %GameObjectTemplate{} = template ->
        Logger.info("CMSG_GAMEOBJECT_QUERY: #{entry} - #{guid}",
          target_name: template.name
        )

        Outbound.send_packet(%Message.SmsgGameobjectQueryResponse{
          entry_id: template.entry,
          info_type: template.type,
          display_id: template.display_id,
          name1: template.name,
          name2: "",
          name3: "",
          name4: "",
          name5: "",
          raw_data: template.data
        })

      _ ->
        Outbound.send_packet(%Message.SmsgGameobjectQueryResponse{entry_id: entry, info_type: nil})
    end

    state
  end

  def handle(%Message.CmsgItemNameQuery{item_id: item_id, guid: _guid}, state) do
    case ItemLoader.get_template(item_id) do
      nil ->
        state

      item ->
        Logger.info("CMSG_ITEM_NAME_QUERY: #{item.name}")

        Outbound.send_packet(%Message.SmsgItemNameQueryResponse{
          item_id: item_id,
          item_name: item.name
        })

        state
    end
  end

  def handle(%Message.CmsgItemQuerySingle{item_id: item_id, guid: _guid}, state) do
    Logger.info("CMSG_ITEM_QUERY_SINGLE: #{item_id}")

    item = ItemLoader.get_template(item_id)

    Outbound.send_packet(%Message.SmsgItemQuerySingleResponse{
      item_id: item_id,
      item: item
    })

    state
  end

  def handle(%Message.CmsgNameQuery{guid: guid}, state) do
    info = name_info(guid)
    Logger.info("CMSG_NAME_QUERY", target_name: info.name)

    Outbound.send_packet(%Message.SmsgNameQueryResponse{
      guid: guid,
      character_name: info.name,
      realm_name: info.realm,
      race: info.race,
      gender: info.gender,
      class: info.class
    })

    state
  end

  def handle(%Message.CmsgNpcTextQuery{text_id: text_id}, state) do
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

        Outbound.send_packet(%Message.SmsgNpcTextUpdate{
          text_id: text_id,
          texts: texts
        })

        state
    end
  end

  def handle(%Message.CmsgPageTextQuery{page_id: page_id}, state) do
    send_pages(page_id, MapSet.new())
    state
  end

  def handle(%Message.CmsgPetNameQuery{pet_number: number, pet_guid: guid}, state), do: Pets.query(state, guid, number)

  def handle(%Message.CmsgQueryTime{}, state), do: Login.query_time(state)

  def handle(%Message.CmsgQuestQuery{quest_id: quest_id}, state) do
    case QuestLoader.get(quest_id) do
      %Quest{} = quest ->
        Outbound.send_packet(%Message.SmsgQuestQueryResponse{quest: quest})

      nil ->
        :ok
    end

    state
  end

  defp display_id(guid, %CreatureTemplate{} = ct) do
    case Metadata.query(guid, [:display_id]) do
      %{display_id: display_id} when is_integer(display_id) and display_id > 0 -> display_id
      _ -> ct.display_id
    end
  end

  defp name_info(guid) do
    case Metadata.query(guid, [:name, :realm, :race, :gender, :class]) do
      %{name: name} = info when is_binary(name) ->
        %{
          name: name,
          realm: Map.get(info, :realm, ""),
          race: Map.get(info, :race, 0),
          gender: Map.get(info, :gender, 0),
          class: Map.get(info, :class, 0)
        }

      _ ->
        offline_name_info(guid)
    end
  end

  defp offline_name_info(guid) do
    case CharacterStore.get(Guid.low_guid(guid)) do
      %Character{} = c ->
        %{name: c.internal.name, realm: "", race: c.unit.race, gender: c.unit.gender, class: c.unit.class}

      _ ->
        %{name: "Unknown", realm: "", race: 0, gender: 0, class: 0}
    end
  end

  defp send_pages(page_id, seen) when is_integer(page_id) and page_id > 0 do
    if MapSet.member?(seen, page_id) do
      :ok
    else
      next_page = send_page(page_id)
      send_pages(next_page, MapSet.put(seen, page_id))
    end
  end

  defp send_pages(_page_id, _seen), do: :ok

  defp send_page(page_id) do
    case PageTextLoader.get(page_id) do
      %{text: text, next_page: next_page} ->
        Outbound.send_packet(%Message.SmsgPageTextQueryResponse{page_id: page_id, text: text, next_page: next_page})
        next_page

      nil ->
        Outbound.send_packet(%Message.SmsgPageTextQueryResponse{page_id: page_id, text: @missing_page_text})
        0
    end
  end
end
