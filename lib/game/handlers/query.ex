defmodule ThistleTea.Game.Query do
  use ThistleTea.Opcodes, [
    :CMSG_NAME_QUERY,
    :SMSG_NAME_QUERY_RESPONSE,
    :CMSG_ITEM_QUERY_SINGLE,
    :SMSG_ITEM_QUERY_SINGLE_RESPONSE,
    :CMSG_GAMEOBJECT_QUERY,
    :SMSG_GAMEOBJECT_QUERY_RESPONSE,
    :CMSG_ITEM_NAME_QUERY,
    :SMSG_ITEM_NAME_QUERY_RESPONSE,
    :CMSG_CREATURE_QUERY,
    :SMSG_CREATURE_QUERY_RESPONSE,
    :CMSG_WHO,
    :SMSG_WHO
  ]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgWho.WhoPlayer
  alias ThistleTea.Util

  require Logger

  # prevent collisions
  @creature_guid_offset 0xF1300000
  @game_object_guid_offset 0xF1100000

  def handle_packet(@cmsg_name_query, body, state) do
    <<guid::little-size(64)>> = body
    [{^guid, character_name, realm_name, race, gender, class}] = :ets.lookup(:guid_name, guid)

    Logger.info("CMSG_NAME_QUERY", target_name: character_name)

    Util.send_packet(%Message.SmsgNameQueryResponse{
      guid: guid,
      character_name: character_name,
      realm_name: realm_name,
      race: race,
      gender: gender,
      class: class
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_item_query_single, body, state) do
    <<item_id::little-size(32), _guid::little-size(64)>> = body
    Logger.info("CMSG_ITEM_QUERY_SINGLE: #{item_id}")

    item = Mangos.Repo.get(Mangos.ItemTemplate, item_id)

    Util.send_packet(%Message.SmsgItemQuerySingleResponse{
      item_id: item_id,
      item: item
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_item_name_query, body, state) do
    <<item_id::little-size(32), _guid::little-size(64)>> = body
    item = Mangos.Repo.get(Mangos.ItemTemplate, item_id)
    Logger.info("CMSG_ITEM_NAME_QUERY: #{item.name}")

    Util.send_packet(%Message.SmsgItemNameQueryResponse{
      item_id: item_id,
      item_name: item.name
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_gameobject_query, body, state) do
    <<entry::little-size(32), guid::little-size(64)>> = body

    game_object =
      Mangos.Repo.get(Mangos.GameObject, guid - @game_object_guid_offset)
      |> Mangos.Repo.preload(:game_object_template)

    template = game_object.game_object_template

    Logger.info("CMSG_GAMEOBJECT_QUERY: #{entry} - #{guid}",
      target_name: template.name
    )

    data = [
      template.data0,
      template.data1,
      template.data2,
      template.data3,
      template.data4,
      template.data5,
      template.data6,
      template.data7,
      template.data8,
      template.data9,
      template.data10,
      template.data11,
      template.data12,
      template.data13,
      template.data14,
      template.data15,
      template.data16,
      template.data17,
      template.data18,
      template.data19,
      template.data20,
      template.data21,
      template.data22,
      template.data23
    ]

    Util.send_packet(%Message.SmsgGameobjectQueryResponse{
      entry_id: template.entry,
      info_type: template.type,
      display_id: template.display_id,
      name1: template.name,
      name2: "",
      name3: "",
      name4: "",
      name5: "",
      raw_data: data
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_creature_query, body, state) do
    <<entry::little-size(32), guid::little-size(64)>> = body

    creature =
      Mangos.Repo.get_by(Mangos.Creature, guid: guid - @creature_guid_offset)
      |> Mangos.Repo.preload(:creature_template)

    ct = creature.creature_template

    Logger.info("CMSG_CREATURE_QUERY",
      target_name: ct.name
    )

    Util.send_packet(%Message.SmsgCreatureQueryResponse{
      creature_entry: entry,
      found: true,
      name1: ct.name,
      name2: "",
      name3: "",
      name4: "",
      sub_name: ct.sub_name,
      type_flags: ct.creature_type_flags,
      creature_type: ct.creature_type,
      creature_family: ct.family,
      creature_rank: ct.rank,
      unknown0: 0,
      spell_data_id: 0,
      display_id: creature.modelid,
      civilian: ct.civilian,
      racial_leader: ct.racial_leader
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_who, _body, state) do
    characters =
      ThistleTea.Character.get_all()
      |> Enum.filter(fn c -> :ets.member(:entities, c.id) end)

    count = Enum.count(characters)

    players =
      characters
      |> Enum.map(fn c ->
        %WhoPlayer{
          name: c.name,
          guild: "Test Guild",
          level: c.level,
          class: c.class,
          race: c.race,
          area: c.area
        }
      end)

    Util.send_packet(%Message.SmsgWho{
      listed_players: count,
      online_players: count,
      players: players
    })

    {:continue, state}
  end
end
