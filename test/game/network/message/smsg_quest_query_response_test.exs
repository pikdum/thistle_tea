defmodule ThistleTea.Game.Network.Message.SmsgQuestQueryResponseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Network.Message.SmsgQuestQueryResponse

  test "serializes a kill quest with rewards" do
    quest = %Quest{
      id: 33,
      method: 2,
      level: 8,
      zone_or_sort: 12,
      type: 0,
      next_quest_in_chain: 0,
      reward_money: 150,
      reward_money_max_level: 540,
      src_item_id: 0,
      flags: 0,
      reward_items: [{80, 1}],
      reward_choice_items: [{90, 1}, {91, 1}],
      title: "T",
      objectives_text: "O",
      details: "D",
      end_text: "E",
      objective_texts: ["a", "", "", ""],
      objective_slots: [
        %{creature_or_go_id: 299, creature_or_go_count: 8, item_id: 0, item_count: 0},
        %{creature_or_go_id: -55, creature_or_go_count: 2, item_id: 0, item_count: 0},
        %{creature_or_go_id: 0, creature_or_go_count: 0, item_id: 0, item_count: 0},
        %{creature_or_go_id: 0, creature_or_go_count: 0, item_id: 0, item_count: 0}
      ]
    }

    binary = SmsgQuestQueryResponse.to_binary(%SmsgQuestQueryResponse{quest: quest})

    <<id::little-size(32), method::little-size(32), level::little-size(32), zone::little-signed-size(32),
      _type::little-size(32), _rep::binary-size(16), next_chain::little-size(32), money::little-signed-size(32),
      money_max::little-size(32), _spell::little-size(32), _src_item::little-size(32), _flags::little-size(32),
      rew1_id::little-size(32), rew1_count::little-size(32), _rest_rewards::binary-size(24),
      choice1_id::little-size(32), _choice1_count::little-size(32), rest::binary>> = binary

    assert {id, method, level, zone} == {33, 2, 8, 12}
    assert next_chain == 0
    assert {money, money_max} == {150, 540}
    assert {rew1_id, rew1_count} == {80, 1}
    assert choice1_id == 90

    <<_rest_choices::binary-size(40), _point::binary-size(16), strings_and_objectives::binary>> =
      rest

    assert <<"T", 0, "O", 0, "D", 0, "E", 0, objectives::binary>> = strings_and_objectives

    <<c1::little-size(32), c1_count::little-size(32), 0::size(64), c2::little-size(32), c2_count::little-size(32),
      _rest2::binary>> = objectives

    assert {c1, c1_count} == {299, 8}
    assert c2 == Bitwise.bor(55, 0x80000000)
    assert c2_count == 2

    assert String.ends_with?(binary, <<"a", 0, 0, 0, 0>>)
  end

  test "hidden rewards flag zeroes money and reward items" do
    quest = %Quest{
      id: 1,
      flags: 0x200,
      reward_money: 999,
      reward_items: [{80, 1}],
      objective_texts: ["", "", "", ""],
      objective_slots: List.duplicate(%{creature_or_go_id: 0, creature_or_go_count: 0, item_id: 0, item_count: 0}, 4)
    }

    binary = SmsgQuestQueryResponse.to_binary(%SmsgQuestQueryResponse{quest: quest})

    <<_head::binary-size(40), money::little-signed-size(32), _money_max::little-size(32), _spell::little-size(32),
      _src_item::little-size(32), _flags::little-size(32), reward_block::binary-size(80), _rest::binary>> = binary

    assert money == 0
    assert reward_block == <<0::size(640)>>
  end
end
