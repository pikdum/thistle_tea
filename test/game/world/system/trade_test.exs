defmodule ThistleTea.Game.World.System.TradeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.Entity.Data.Trade.Cast, as: TradeCast
  alias ThistleTea.Game.Entity.Data.Trade.Decision
  alias ThistleTea.Game.Entity.Data.Trade.Prepare
  alias ThistleTea.Game.Entity.Data.Trade.Receipt
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Trade, as: PlayerTrade
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.System.Trade
  alias ThistleTea.Game.WorldRef

  setup [:build_session]

  describe "exchange lifecycle" do
    test "commits both sides together and recovers each owner exactly once", context do
      %{server: server, first: first, second: second, first_item: first_item, second_item: second_item} = context
      id = prepare_exchange(context)
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      assert ItemStore.get(first_item.object.guid).item.owner == first.object.guid
      assert ItemStore.pending_trade(first.object.guid) == nil
      assert :ok = as_owner(context, second, fn -> Trade.prepared(server, id, second, %{}) end)
      assert %Receipt{id: ^id} = ItemStore.pending_trade(first.object.guid)
      assert %Receipt{id: ^id} = ItemStore.pending_trade(second.object.guid)
      assert ItemStore.get(first_item.object.guid).item.owner == second.object.guid
      assert ItemStore.get(second_item.object.guid).item.owner == first.object.guid

      GenServer.stop(server)
      recovered = PlayerTrade.recover(first)
      assert recovered.player.inv1 == second_item.object.guid
      assert recovered.player.coinage == 925
      assert recovered.internal.last_trade_id == id
      spent = %{recovered | player: %{recovered.player | coinage: 900}}
      assert PlayerTrade.recover(spent).player.coinage == 900
      assert PlayerTrade.recover(second).player.coinage == 1075
      assert PlayerTrade.recover(second).player.inv1 == first_item.object.guid
    end

    test "aborts when an owner disconnects before the second preparation", context do
      %{server: server, first: first, second: second, owners: owners, first_item: item} = context
      id = prepare_exchange(context)
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      Process.exit(owners[second.object.guid], :kill)
      guid = first.object.guid
      assert_receive {:packet, ^guid, %Message.SmsgTradeStatus{status: :trade_canceled}}, 1_000
      assert_receive {:owner_message, ^guid, %Decision{id: ^id}}, 1_000
      assert ItemStore.pending_trade(guid) == nil
      assert ItemStore.get(item.object.guid) == item
      assert :stale = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
    end

    test "a preparation timeout releases both owners without exchanging", context do
      %{server: server, first: first, first_item: item} = context
      id = prepare_exchange(context)
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      send(server, {:prepare_timeout, id})
      guid = first.object.guid
      assert_receive {:owner_message, ^guid, %Decision{id: ^id}}
      assert ItemStore.pending_trade(guid) == nil
      assert ItemStore.get(item.object.guid) == item
    end

    test "moving away cancels and stale preparation cannot revive the trade", context do
      %{server: server, first: first, second: second, table: table} = context
      id = prepare_exchange(context)
      :ets.insert(table, {second.object.guid, {WorldRef.open(0), 20.0, 0.0, 0.0}})
      send(server, :check)
      guid = first.object.guid
      assert_receive {:packet, ^guid, %Message.SmsgTradeStatus{status: :trade_canceled}}
      assert :stale = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      assert ItemStore.pending_trade(guid) == nil
    end

    test "revalidates actual inventory positions before committing", context do
      %{server: server, first: first, second: second, second_item: item} = context
      id = prepare_exchange(context)
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      moved = %{second | player: %{second.player | inv1: 0, bank1: item.object.guid}}
      assert :ok = as_owner(context, second, fn -> Trade.prepared(server, id, moved, %{}) end)
      guid = second.object.guid
      assert_receive {:packet, ^guid, %Message.SmsgTradeStatus{status: :close_window, inventory_result: 23}}
      assert ItemStore.pending_trade(guid) == nil
      assert ItemStore.get(item.object.guid) == item
    end
  end

  describe "trade opening lifecycle" do
    setup [:build_opening]

    test "commits the unlock and skill gain once, retaining private ownership through recovery", context do
      %{first: first, second: second, server: server, second_item: target} = context
      id = prepare_opening(context)
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      refute Item.unlocked?(ItemStore.get(target.object.guid))
      assert ItemStore.pending_trade(first.object.guid) == nil
      assert :ok = as_owner(context, second, fn -> Trade.prepared(server, id, second, %{}) end)
      item = ItemStore.get(target.object.guid)
      assert Item.unlocked?(item)
      assert item.item.owner == second.object.guid
      refute Item.loot_generated?(item)
      assert ItemStore.pending_trade(first.object.guid).changes.player.skills[633].value == 2

      GenServer.stop(server)
      recovered = PlayerTrade.recover(first)
      assert recovered.player.skills[633].value == 2
      assert recovered.player.coinage == 1075
      assert PlayerTrade.recover(recovered) == recovered
      owner = PlayerTrade.recover(second)
      assert owner.player.coinage == 925
      assert owner.player.inv1 == target.object.guid
      assert CharacterStore.get(second.object.guid) == owner
    end

    test "disconnect before both snapshots commit preserves the locked source and both balances", context do
      %{first: first, second: second, owners: owners, server: server, second_item: target} = context
      id = prepare_opening(context)
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      Process.exit(owners[second.object.guid], :kill)
      guid = first.object.guid
      assert_receive {:packet, ^guid, %Message.SmsgTradeStatus{status: :trade_canceled}}, 1_000
      assert ItemStore.get(target.object.guid) == target
      assert ItemStore.pending_trade(guid) == nil
      assert PlayerTrade.recover(first).player.coinage == 1000
      assert PlayerTrade.recover(first).player.skills[633].value == 1
      assert PlayerTrade.recover(second).player.coinage == 1000
    end

    test "failed casts clear their preview and retry without accepting stale preparation", context do
      %{first: first, second: second, server: server, second_item: target} = context
      previous_id = prepare_opening(context)
      without_tool = %{first | player: %{first.player | inv2: 0}}
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, previous_id, without_tool, %{}) end)
      assert :ok = as_owner(context, second, fn -> Trade.prepared(server, previous_id, second, %{}) end)
      guid = first.object.guid
      failure = Message.SmsgCastResult.failure(1804, :item_gone)
      assert_receive {:packet, ^guid, ^failure}
      assert_receive {:packet, ^guid, %Message.SmsgTradeStatus{status: :back_to_trade}}
      assert {:ok, id, ^target, offer} = request(context, first, :spell_target)
      assert id != previous_id
      assert offer.spell == nil
      refute offer.accepted?
      assert ItemStore.pending_trade(guid) == nil
      refute Item.unlocked?(ItemStore.get(target.object.guid))
      send(server, {:prepare_timeout, previous_id})
      assert :stale = as_owner(context, first, fn -> Trade.prepared(server, previous_id, first, %{}) end)
      assert :ok = as_owner(context, first, fn -> Trade.abort(server, previous_id, guid) end)
      assert {:error, :not_trading} = request(context, first, {:spell, previous_id, context.cast})
      assert {:ok, ^id, ^target, _offer} = request(context, first, :spell_target)

      assert :ok = request(context, first, {:spell, id, context.cast})
      :ets.insert(context.table, {:now, 400})
      assert :ok = request(context, first, :accept)
      assert :ok = request(context, second, :accept)
      assert_receive {:owner_message, _guid, %Prepare{id: ^id}}
      assert_receive {:owner_message, _guid, %Prepare{id: ^id}}
      assert :ok = as_owner(context, first, fn -> Trade.prepared(server, id, first, %{}) end)
      assert :ok = as_owner(context, second, fn -> Trade.prepared(server, id, second, %{}) end)
      assert %Receipt{id: ^id} = ItemStore.pending_trade(guid)
      assert Item.unlocked?(ItemStore.get(target.object.guid))
      assert PlayerTrade.recover(first).player.coinage == 1075
      assert PlayerTrade.recover(first).player.skills[633].value == 2
      assert PlayerTrade.recover(second).player.coinage == 925
    end
  end

  defp build_opening(context) do
    spell = %Spell{id: 1804, tools: [5060], effects: [%Effect{type: :open_lock, misc_value: 1, base_points: -1}]}
    target = ItemStore.create(%ItemTemplate{entry: 4632, flags: 4, lockid: 5}, owner: context.second.object.guid)
    tool = ItemStore.create(%ItemTemplate{entry: 5060}, owner: context.first.object.guid)
    first = context.first
    second = context.second

    first = %{
      first
      | unit: %Unit{health: 100, class: 4, race: 1, level: 20},
        player: %{first.player | inv2: tool.object.guid, skills: %{633 => %{value: 1, max: 100}}},
        internal: %{first.internal | spellbook: %{1804 => spell}}
    }

    cast = %TradeCast{
      spell: spell,
      target_guid: target.object.guid,
      effects: [],
      lock: %Lock{id: 5, requirements: [%Requirement{type: :skill, index: 1, skill: 1}]},
      skill_roll: 0
    }

    %{
      first: first,
      second: %{second | player: %{second.player | inv1: target.object.guid}},
      second_item: target,
      cast: cast
    }
  end

  defp prepare_opening(context) do
    %{first: first, second: second, server: server, table: table} = context
    assert :ok = request(context, first, {:initiate, second.object.guid})
    assert :ok = request(context, second, :open)
    assert :ok = request(context, second, {:item, 6, context.second_item})
    assert :ok = request(context, second, {:money, 75})
    assert {:ok, id, item, _offer} = request(context, first, :spell_target)
    assert item == context.second_item
    assert :ok = request(context, first, {:spell, id, context.cast})
    :ets.insert(table, {:now, 200})
    assert :ok = request(context, first, :accept)
    assert :ok = request(context, second, :accept)
    assert_receive {:owner_message, _guid, %Prepare{id: ^id, coordinator: ^server}}
    assert_receive {:owner_message, _guid, %Prepare{id: ^id, coordinator: ^server}}
    id
  end

  defp build_session(_context) do
    parent = self()
    first = character()
    second = character()
    first_item = ItemStore.create(%ItemTemplate{entry: 10}, owner: first.object.guid)
    second_item = ItemStore.create(%ItemTemplate{entry: 20}, owner: second.object.guid)
    first = %{first | player: %{first.player | inv1: first_item.object.guid}}
    second = %{second | player: %{second.player | inv1: second_item.object.guid}}

    owners =
      Map.new([first, second], fn character ->
        guid = character.object.guid
        {guid, spawn(fn -> owner_loop(parent, guid) end)}
      end)

    table = :ets.new(:trade_positions, [:public, :set])
    Enum.each([first, second], &:ets.insert(table, {&1.object.guid, {WorldRef.open(0), 0.0, 0.0, 0.0}}))
    :ets.insert(table, {:now, 0})

    server =
      start_supervised!(
        {Trade,
         name: nil,
         owner: &Map.get(owners, &1),
         position: fn guid -> :ets.lookup_element(table, guid, 2) end,
         now: fn -> :ets.lookup_element(table, :now, 2) end,
         metadata: fn _guid -> %{race: 1, alive?: true, unit_flags: 0} end,
         packet: fn packet, guid -> send(parent, {:packet, guid, packet}) end,
         get_enchantment: fn _id -> nil end}
      )

    on_exit(fn -> Enum.each(owners, &cleanup_owner/1) end)

    %{
      server: server,
      first: first,
      second: second,
      owners: owners,
      table: table,
      first_item: first_item,
      second_item: second_item
    }
  end

  defp cleanup_owner({guid, pid}) do
    Process.exit(pid, :kill)
    if receipt = ItemStore.pending_trade(guid), do: ItemStore.acknowledge_trade(receipt)
  end

  defp character do
    CharacterStore.create(%Character{
      id: 0,
      object: %Object{},
      player: %Player{coinage: 1000},
      unit: %Unit{race: 1},
      internal: %Internal{}
    })
  end

  defp prepare_exchange(context) do
    %{first: first, second: second, first_item: first_item, second_item: second_item, server: server, table: table} =
      context

    assert :ok = request(context, first, {:initiate, second.object.guid})
    assert :ok = request(context, second, :open)
    assert :ok = request(context, first, {:item, 0, first_item})
    assert :ok = request(context, second, {:item, 0, second_item})
    assert :ok = request(context, first, {:money, 100})
    assert :ok = request(context, second, {:money, 25})
    :ets.insert(table, {:now, 200})
    assert :ok = request(context, first, :accept)
    assert :ok = request(context, second, :accept)
    assert_receive {:owner_message, _guid, %Prepare{id: id, coordinator: ^server}}
    assert_receive {:owner_message, _guid, %Prepare{id: ^id, coordinator: ^server}}
    id
  end

  defp request(context, character, action) do
    as_owner(context, character, fn -> Trade.request(character.object.guid, action, context.server) end)
  end

  defp as_owner(context, character, fun) do
    ref = make_ref()
    send(context.owners[character.object.guid], {:call, self(), ref, fun})
    assert_receive {^ref, result}, 1_000
    result
  end

  defp owner_loop(parent, guid) do
    receive do
      {:call, from, ref, fun} -> send(from, {ref, fun.()})
      message -> send(parent, {:owner_message, guid, message})
    end

    owner_loop(parent, guid)
  end
end
