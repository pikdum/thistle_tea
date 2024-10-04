defmodule ThistleTea.Game.Query do
  import ThistleTea.Util, only: [send_packet: 2]

  alias ThistleTea.Mangos

  require Logger

  # prevent collisions
  @creature_guid_offset 0xF1300000
  @game_object_guid_offset 0xF1100000

  @cmsg_name_query 0x050
  @smsg_name_query_response 0x051

  @cmsg_item_query_single 0x056
  @smsg_item_query_single_response 0x058

  @cmsg_gameobject_query 0x05E
  @smsg_gameobject_query_response 0x05F

  @cmsg_item_name_query 0x2C4
  @smsg_item_name_query_response 0x2C5

  @cmsg_creature_query 0x060
  @smsg_creature_query_response 0x061

  @cmsg_who 0x62
  @smsg_who 0x63

  def handle_packet(@cmsg_name_query, body, state) do
    <<guid::little-size(64)>> = body
    [{^guid, character_name, realm_name, race, gender, class}] = :ets.lookup(:guid_name, guid)

    Logger.info("CMSG_NAME_QUERY", target_name: character_name)

    send_packet(
      @smsg_name_query_response,
      <<guid::little-size(64)>> <>
        character_name <> <<0>> <> realm_name <> <<0>> <> <<race, gender, class>>
    )

    {:continue, state}
  end

  def handle_packet(@cmsg_item_query_single, body, state) do
    <<item_id::little-size(32), guid::little-size(64)>> = body
    Logger.info("CMSG_ITEM_QUERY_SINGLE: #{item_id} - #{guid}")

    item = Mangos.get(ItemTemplate, item_id)

    packet =
      <<item_id::little-size(32)>> <>
        if item do
          <<item.class::little-size(32), item.subclass::little-size(32)>> <>
            item.name <>
            <<0, 0, 0, 0>> <>
            <<
              # item info
              item.display_id::little-size(32),
              item.quality::little-size(32),
              item.flags::little-size(32),
              item.buy_price::little-size(32),
              item.sell_price::little-size(32),
              item.inventory_type::little-size(32),
              item.allowable_class::little-size(32),
              item.allowable_race::little-size(32),
              item.item_level::little-size(32),
              item.required_level::little-size(32),
              item.required_skill::little-size(32),
              item.required_skill_rank::little-size(32),
              item.required_spell::little-size(32),
              item.required_honor_rank::little-size(32),
              item.required_city_rank::little-size(32),
              item.required_reputation_faction::little-size(32),
              item.required_reputation_rank::little-size(32),
              item.max_count::little-size(32),
              item.stackable::little-size(32),
              item.container_slots::little-size(32)
            >> <>
            <<
              # item stats
              item.stat_type1::little-size(32),
              item.stat_value1::little-size(32),
              item.stat_type2::little-size(32),
              item.stat_value2::little-size(32),
              item.stat_type3::little-size(32),
              item.stat_value3::little-size(32),
              item.stat_type4::little-size(32),
              item.stat_value4::little-size(32),
              item.stat_type5::little-size(32),
              item.stat_value5::little-size(32),
              item.stat_type6::little-size(32),
              item.stat_value6::little-size(32),
              item.stat_type7::little-size(32),
              item.stat_value7::little-size(32),
              item.stat_type8::little-size(32),
              item.stat_value8::little-size(32),
              item.stat_type9::little-size(32),
              item.stat_value9::little-size(32),
              item.stat_type10::little-size(32),
              item.stat_value10::little-size(32),
              # item damage
              item.dmg_min1::little-float-size(32),
              item.dmg_max1::little-float-size(32),
              item.dmg_type1::little-size(32),
              item.dmg_min2::little-float-size(32),
              item.dmg_max2::little-float-size(32),
              item.dmg_type2::little-size(32),
              item.dmg_min3::little-float-size(32),
              item.dmg_max3::little-float-size(32),
              item.dmg_type3::little-size(32),
              item.dmg_min4::little-float-size(32),
              item.dmg_max4::little-float-size(32),
              item.dmg_type4::little-size(32),
              item.dmg_min5::little-float-size(32),
              item.dmg_max5::little-float-size(32),
              item.dmg_type5::little-size(32),
              # item armor
              item.armor::little-size(32),
              # item resistances
              item.holy_res::little-size(32),
              item.fire_res::little-size(32),
              item.nature_res::little-size(32),
              item.frost_res::little-size(32),
              item.shadow_res::little-size(32),
              item.arcane_res::little-size(32),
              # misc
              item.delay::little-size(32),
              item.ammo_type::little-size(32),
              item.ranged_mod_range::little-float-size(32),
              # item spells
              item.spellid_1::little-size(32),
              item.spelltrigger_1::little-size(32),
              item.spellcharges_1::little-size(32),
              item.spellcooldown_1::little-size(32),
              item.spellcategory_1::little-size(32),
              item.spellcategorycooldown_1::little-size(32),
              item.spellid_2::little-size(32),
              item.spelltrigger_2::little-size(32),
              item.spellcharges_2::little-size(32),
              item.spellcooldown_2::little-size(32),
              item.spellcategory_2::little-size(32),
              item.spellcategorycooldown_2::little-size(32),
              item.spellid_3::little-size(32),
              item.spelltrigger_3::little-size(32),
              item.spellcharges_3::little-size(32),
              item.spellcooldown_3::little-size(32),
              item.spellcategory_3::little-size(32),
              item.spellcategorycooldown_3::little-size(32),
              item.spellid_4::little-size(32),
              item.spelltrigger_4::little-size(32),
              item.spellcharges_4::little-size(32),
              item.spellcooldown_4::little-size(32),
              item.spellcategory_4::little-size(32),
              item.spellcategorycooldown_4::little-size(32),
              item.spellid_5::little-size(32),
              item.spelltrigger_5::little-size(32),
              item.spellcharges_5::little-size(32),
              item.spellcooldown_5::little-size(32),
              item.spellcategory_5::little-size(32),
              item.spellcategorycooldown_5::little-size(32),
              # misc
              item.bonding::little-size(32)
            >> <>
            item.description <>
            <<
              # and even more
              0,
              item.page_text::little-size(32),
              item.language_id::little-size(32),
              item.page_material::little-size(32),
              item.start_quest::little-size(32),
              item.lockid::little-size(32),
              item.material::little-size(32),
              item.sheath::little-size(32),
              item.random_property::little-size(32),
              item.block::little-size(32),
              item.item_set::little-size(32),
              item.max_durability::little-size(32),
              item.area::little-size(32),
              item.map::little-size(32),
              item.bag_family::little-size(32)
            >>
        else
          <<>>
        end

    send_packet(@smsg_item_query_single_response, packet)
    {:continue, state}
  end

  def handle_packet(@cmsg_item_name_query, body, state) do
    # TODO: am i not getting guid because i'm not sending a create object packet first?
    <<item_id::little-size(32), _guid::little-size(64)>> = body
    item = Mangos.get(ItemTemplate, item_id)
    Logger.info("CMSG_ITEM_NAME_QUERY: #{item.name}")
    packet = <<item_id::little-size(32)>> <> item.name <> <<0>>

    send_packet(@smsg_item_name_query_response, packet)
    {:continue, state}
  end

  def handle_packet(@cmsg_gameobject_query, body, state) do
    <<entry::little-size(32), guid::little-size(64)>> = body

    game_object =
      Mangos.get(GameObject, guid - @game_object_guid_offset)
      |> Mangos.preload(:game_object_template)

    template = game_object.game_object_template

    Logger.info("CMSG_GAMEOBJECT_QUERY: #{entry} - #{guid}",
      target_name: template.name
    )

    data =
      [
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
      |> Enum.reduce(<<>>, fn x, acc -> acc <> <<x::little-size(32)>> end)

    payload =
      <<
        template.entry::little-size(32),
        template.type::little-size(32),
        template.display_id::little-size(32)
      >> <>
        template.name <>
        <<
          0,
          # name 2
          0,
          # name 3
          0,
          # name 4
          0,
          # name 5
          0
        >> <> data

    send_packet(@smsg_gameobject_query_response, payload)

    {:continue, state}
  end

  def handle_packet(@cmsg_creature_query, body, state) do
    <<entry::little-size(32), guid::little-size(64)>> = body

    creature =
      Mangos.get_by(Creature, guid: guid - @creature_guid_offset)
      |> Mangos.preload(:creature_template)

    ct = creature.creature_template

    Logger.info("CMSG_CREATURE_QUERY",
      target_name: ct.name
    )

    send_packet(
      @smsg_creature_query_response,
      <<entry::little-size(32)>> <>
        ct.name <>
        <<
          0,
          # names 2-4
          0,
          0,
          0
        >> <>
        if ct.sub_name do
          ct.sub_name <> <<0>>
        else
          <<0>>
        end <>
        <<
          # the rest
          ct.creature_type_flags::little-size(32),
          ct.creature_type::little-size(32),
          ct.family::little-size(32),
          ct.rank::little-size(32),
          # unknown
          0::little-size(32),
          # spell data
          0::little-size(32),
          creature.modelid::little-size(32),
          # civilian
          0,
          # leader
          0
        >>
    )

    {:continue, state}
  end

  def handle_packet(@cmsg_who, _body, state) do
    # get all logged in characters
    characters =
      ThistleTea.Character.get_all()
      |> Enum.filter(fn c -> :ets.member(:entities, c.id) end)

    count = Enum.count(characters)

    listed_players =
      characters
      |> Enum.map(fn c ->
        c.name <>
          <<0>> <>
          "Test Guild" <>
          <<0>> <>
          <<
            c.level::little-size(32),
            c.class::little-size(32),
            c.race::little-size(32),
            c.area::little-size(32)
            # https://gtker.com/wow_messages/docs/smsg_who.html
            # looks like docs are for an older version?
          >>
      end)
      |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)

    send_packet(
      @smsg_who,
      <<count::little-size(32), count::little-size(32)>> <> listed_players
    )

    {:continue, state}
  end
end
