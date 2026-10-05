defmodule ThistleTea.Game.World.Entity.Player.BattlegroundSuppliesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.BattlegroundSupplies
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Battleground.Match
  alias ThistleTea.Test.Unique

  defmodule Catalog do
    @moduledoc false
    def template_for_map(30),
      do: %Template{
        type_id: 1,
        map_id: 30,
        min_level: 51,
        max_level: 60,
        min_players_per_team: 1,
        max_players_per_team: 40,
        alliance_start: {0.0, 0.0, 0.0, 0.0},
        horde_start: {0.0, 0.0, 0.0, 0.0}
      }

    def template_for_map(_map), do: nil
  end

  setup [:supplied_match]

  describe "take_beacon/4" do
    test "commits one beacon and receipt before a stale selection can take more", context do
      state = BattlegroundSupplies.take_beacon(context.state, 13_179, 0, battleground_system: context.server)
      assert Inventory.count_entry(state.character.player, 17_324, &ItemStore.get/1) == 1
      assert Match.snapshot(context.match).air[13_179].count == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{item_id: 17_324, count: 1}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
      assert BattlegroundSupplies.take_beacon(state, 13_179, 0, battleground_system: context.server) == state
      assert Inventory.count_entry(state.character.player, 17_324, &ItemStore.get/1) == 1
    end

    test "full bags and an existing bank beacon do not spend supplies", context do
      for variant <- [:full, :bank] do
        character = occupied(context.state.character, variant)
        state = %{context.state | character: character}
        before = Match.snapshot(context.match)
        assert BattlegroundSupplies.take_beacon(state, 13_179, 0, battleground_system: context.server) == state
        assert Match.snapshot(context.match) == before
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{}}}
      end
    end

    test "parallel requests serialize against the shared stockpile", context do
      replies =
        1..8
        |> Task.async_stream(fn _ -> Match.take_beacon(context.match, context.state.guid, 13_179, 0) end)
        |> Enum.map(fn {:ok, reply} -> reply end)

      assert Enum.count(replies, &(&1 == {:ok, 17_324})) == 1
      assert Enum.count(replies, &(&1 == {:error, :unavailable})) == 7
      assert Match.snapshot(context.match).air[13_179].count == 0
    end
  end

  describe "take_orders/4" do
    test "commits one order and receipt and deploys only once", context do
      state = BattlegroundSupplies.take_orders(context.state, 12_097, 9_000, battleground_system: context.server)
      assert Inventory.count_entry(state.character.player, 17_442, &ItemStore.get/1) == 1
      assert Match.snapshot(context.match).ground.horde.phase == :assembled
      assert Match.snapshot(context.match).ground.horde.irondeep == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{item_id: 17_442, count: 1}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
      assert BattlegroundSupplies.take_orders(state, 12_097, 9_000, battleground_system: context.server) == state
      assert Inventory.count_entry(state.character.player, 17_442, &ItemStore.get/1) == 1
    end

    test "full bags and an existing bank order leave the shared stockpile ready", context do
      for variant <- [:full, :bank] do
        character = occupied(context.state.character, variant, 17_442)
        state = %{context.state | character: character}
        before = Match.snapshot(context.match)
        assert BattlegroundSupplies.take_orders(state, 12_097, 9_000, battleground_system: context.server) == state
        assert Match.snapshot(context.match) == before
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{}}}
      end
    end

    test "racing requesters cannot duplicate an infantry deployment", context do
      replies =
        1..8
        |> Task.async_stream(fn _ -> Match.take_orders(context.match, context.state.guid, 12_097, 9_000) end)
        |> Enum.map(fn {:ok, reply} -> reply end)

      assert Enum.count(replies, &(&1 == {:ok, 17_442})) == 1
      assert Enum.count(replies, &(&1 == {:error, :unavailable})) == 7
      assert Match.snapshot(context.match).ground.horde.phase == :assembled
    end
  end

  defp occupied(character, variant, entry \\ 17_324)

  defp occupied(character, :bank, entry) do
    item = item(entry, character.object.guid)
    %{character | player: %{character.player | bank1: item.object.guid}}
  end

  defp occupied(character, :full, _entry) do
    fields =
      Map.new(1..16, fn slot ->
        {String.to_existing_atom("inv#{slot}"), item(Unique.integer(), character.object.guid).object.guid}
      end)

    %{character | player: struct!(character.player, fields)}
  end

  defp item(entry, owner) do
    template = %ItemTemplate{entry: entry, max_count: if(entry in [17_324, 17_442], do: 1, else: 0), stackable: 1}
    ItemStore.put(Item.build(template, Guid.from_low_guid(:item, Unique.integer()), owner: owner))
  end

  defp supplied_match(_context) do
    guid = Unique.integer()
    opponent = Unique.integer()
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    {:ok, server} =
      BattlegroundSystem.start_link(
        name: {:global, {__MODULE__, make_ref()}},
        catalog: Catalog,
        match_supervisor: supervisor,
        effect_sink: fn _match, _effects -> :ok end
      )

    assert :ok = BattlegroundSystem.join(%{guid: guid, name: "Horde#{guid}", team: :horde, level: 60}, 30, server)

    assert :ok =
             BattlegroundSystem.join(
               %{guid: opponent, name: "Alliance#{opponent}", team: :alliance, level: 60},
               30,
               server
             )

    assert {:ok, world, _} = BattlegroundSystem.port(guid, 1, nil, server)
    assert :ok = BattlegroundSystem.debug_start_now(world, server)
    match = BattlegroundSystem.match_for_world(world, server)
    assert :close = Match.interact(match, guid, 13_179, :rescue_commander, 0)

    Match.creature_event(match, %Effects.BattlegroundCreatureEvent{
      world: world,
      creature_guid: Guid.from_low_guid(:mob, 13_179, Unique.integer()),
      creature_entry: 13_179,
      event: 1
    })

    for _ <- 1..90, do: Match.quest_rewarded(match, guid, 6_825)
    for _ <- 1..7, do: Match.quest_rewarded(match, guid, 6_985)
    assert Match.snapshot(match).air[13_179].count == 90
    previous = ItemLoader.get_cached_template(17_324)
    previous_orders = ItemLoader.get_cached_template(17_442)
    :ets.insert(ItemLoader, {17_324, %ItemTemplate{entry: 17_324, name: "Guse's Beacon", max_count: 1, stackable: 1}})

    :ets.insert(
      ItemLoader,
      {17_442, %ItemTemplate{entry: 17_442, name: "Frostwolf Assault Orders", max_count: 1, stackable: 1}}
    )

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: %Player{},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    on_exit(fn ->
      if previous, do: :ets.insert(ItemLoader, {17_324, previous}), else: :ets.delete(ItemLoader, 17_324)
      if previous_orders, do: :ets.insert(ItemLoader, {17_442, previous_orders}), else: :ets.delete(ItemLoader, 17_442)
      :ets.delete(CharacterStore, guid)
      for {item_guid, %Item{item: %{owner: ^guid}}} <- :ets.tab2list(ItemStore), do: ItemStore.delete(item_guid)
      Metadata.delete(guid)
    end)

    %{server: server, match: match, state: %State{guid: guid, character: character}}
  end
end
