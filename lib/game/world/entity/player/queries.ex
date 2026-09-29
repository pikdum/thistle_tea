defmodule ThistleTea.Game.World.Entity.Player.Queries do
  @moduledoc """
  Answers the client's cache queries from loader caches, Metadata, and the
  character store. Each function returns the response message, a list of
  them, or `nil` when the client gets no answer: creature and game-object
  templates, item names and templates, unit names (offline characters
  included), NPC texts, page-text chains, and quests.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.CreatureTemplate
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdate
  alias ThistleTea.Game.Network.Message.SmsgNpcTextUpdate.NpcTextUpdateEmote
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.NpcText, as: NpcTextLoader
  alias ThistleTea.Game.World.Loader.PageText, as: PageTextLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata

  require Logger

  @missing_page_text "Item page missing."

  def creature(entry, guid) do
    case CreatureTemplateLoader.get(entry) do
      %CreatureTemplate{} = template ->
        Logger.info("CMSG_CREATURE_QUERY", target_name: template.name)

        %Message.SmsgCreatureQueryResponse{
          creature_entry: entry,
          found: true,
          name1: template.name,
          name2: "",
          name3: "",
          name4: "",
          sub_name: template.sub_name,
          type_flags: template.type_flags,
          creature_type: template.creature_type,
          creature_family: template.family,
          creature_rank: template.rank,
          unknown0: 0,
          spell_data_id: 0,
          display_id: display_id(guid, template),
          civilian: template.civilian,
          racial_leader: template.racial_leader
        }

      _missing ->
        %Message.SmsgCreatureQueryResponse{creature_entry: entry, found: false}
    end
  end

  def game_object(entry, guid) do
    case GameObjectTemplateLoader.get(entry) do
      %GameObjectTemplate{} = template ->
        Logger.info("CMSG_GAMEOBJECT_QUERY: #{entry} - #{guid}", target_name: template.name)

        %Message.SmsgGameobjectQueryResponse{
          entry_id: template.entry,
          info_type: template.type,
          display_id: template.display_id,
          name1: template.name,
          name2: "",
          name3: "",
          name4: "",
          name5: "",
          raw_data: template.data
        }

      _missing ->
        %Message.SmsgGameobjectQueryResponse{entry_id: entry, info_type: nil}
    end
  end

  def item_name(item_id) do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{name: name} ->
        Logger.info("CMSG_ITEM_NAME_QUERY: #{name}")
        %Message.SmsgItemNameQueryResponse{item_id: item_id, item_name: name}

      nil ->
        nil
    end
  end

  def item(item_id) do
    Logger.info("CMSG_ITEM_QUERY_SINGLE: #{item_id}")
    %Message.SmsgItemQuerySingleResponse{item_id: item_id, item: ItemLoader.get_template(item_id)}
  end

  def name(guid) do
    info = name_info(guid)
    Logger.info("CMSG_NAME_QUERY", target_name: info.name)

    %Message.SmsgNameQueryResponse{
      guid: guid,
      character_name: info.name,
      realm_name: info.realm,
      race: info.race,
      gender: info.gender,
      class: info.class
    }
  end

  def npc_text(text_id) do
    case NpcTextLoader.get(text_id) do
      nil -> nil
      groups -> %Message.SmsgNpcTextUpdate{text_id: text_id, texts: Enum.map(groups, &npc_text_update/1)}
    end
  end

  def pages(page_id), do: pages(page_id, MapSet.new())

  def quest(quest_id) do
    case QuestLoader.get(quest_id) do
      %Quest{} = quest -> %Message.SmsgQuestQueryResponse{quest: quest}
      nil -> nil
    end
  end

  defp display_id(guid, %CreatureTemplate{} = template) do
    case Metadata.query(guid, [:display_id]) do
      %{display_id: display_id} when is_integer(display_id) and display_id > 0 -> display_id
      _ -> template.display_id
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

  defp npc_text_update(text) do
    %NpcTextUpdate{
      probability: text.prob,
      texts: [Map.get(text, :text_0), Map.get(text, :text_1)],
      language: text.lang,
      emotes: [
        %NpcTextUpdateEmote{delay: text.em_0_delay, emote: text.em_0},
        %NpcTextUpdateEmote{delay: text.em_1_delay, emote: text.em_1},
        %NpcTextUpdateEmote{delay: text.em_2_delay, emote: text.em_2}
      ]
    }
  end

  defp pages(page_id, seen) when is_integer(page_id) and page_id > 0 do
    if MapSet.member?(seen, page_id) do
      []
    else
      {page, next_page} = page(page_id)
      [page | pages(next_page, MapSet.put(seen, page_id))]
    end
  end

  defp pages(_page_id, _seen), do: []

  defp page(page_id) do
    case PageTextLoader.get(page_id) do
      %{text: text, next_page: next_page} ->
        {%Message.SmsgPageTextQueryResponse{page_id: page_id, text: text, next_page: next_page}, next_page}

      nil ->
        {%Message.SmsgPageTextQueryResponse{page_id: page_id, text: @missing_page_text}, 0}
    end
  end
end
