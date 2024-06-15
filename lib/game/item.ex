defmodule ThistleTea.Game.Item do
  defmacro __using__(_) do
    quote do
      @cmsg_item_query_single 0x056
      @smsg_item_query_single_response 0x058

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_item_query_single, _size, body}, {socket, state}) do
        <<item_id::little-size(32), guid::little-size(64)>> = body
        Logger.info("CMSG_ITEM_QUERY_SINGLE: #{item_id} - #{guid}")

        item = ThistleTea.Mangos.get(ItemTemplate, item_id)

        packet =
          <<item_id::little-size(32)>> <>
            if item do
              <<item.class::big-size(32), item.subclass::big-size(32)>> <>
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
                  item.dmg_min1::float-size(32),
                  item.dmg_max1::float-size(32),
                  item.dmg_type1::little-size(32),
                  item.dmg_min2::float-size(32),
                  item.dmg_max2::float-size(32),
                  item.dmg_type2::little-size(32),
                  item.dmg_min3::float-size(32),
                  item.dmg_max3::float-size(32),
                  item.dmg_type3::little-size(32),
                  item.dmg_min4::float-size(32),
                  item.dmg_max4::float-size(32),
                  item.dmg_type4::little-size(32),
                  item.dmg_min5::float-size(32),
                  item.dmg_max5::float-size(32),
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
                  item.ranged_mod_range::float-size(32),
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
        {:noreply, {socket, state}}
      end
    end
  end
end
