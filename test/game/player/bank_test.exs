defmodule ThistleTea.Game.Player.BankTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Bank
  alias ThistleTea.Game.Player.Inventory, as: PlayerInventory
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @bag_0 255
  @backpack_start 23
  @bank_start 39
  @banker_flag 0x00000100

  setup do
    id = System.unique_integer([:positive, :monotonic])
    banker_guid = Guid.from_low_guid(:mob, 54, id)
    character = character(id)

    Metadata.put(banker_guid, %{npc_flags: @banker_flag, alive?: true})
    SpatialHash.update(:mobs, banker_guid, WorldRef.open(0), 2.0, 0.0, 0.0)
    SpatialHash.update(:players, character.object.guid, WorldRef.open(0), 0.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(banker_guid)
      Metadata.delete(character.object.guid)
      SpatialHash.remove(:mobs, banker_guid)
      SpatialHash.remove(:players, character.object.guid)
    end)

    state = %State{ready: true, guid: character.object.guid, character: character}
    %{banker_guid: banker_guid, state: state}
  end

  describe "activate/2" do
    test "opens a nearby live friendly banker", %{banker_guid: banker_guid, state: state} do
      state = Bank.activate(state, banker_guid)

      assert state.active_banker_guid == banker_guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgShowBank{banker_guid: ^banker_guid}}}
    end

    test "rejects a non-mob GUID and clears a stale capability", %{state: state} do
      state = %{state | active_banker_guid: 123}
      state = Bank.activate(state, Guid.from_low_guid(:player, 99))

      assert state.active_banker_guid == nil
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgShowBank{}}}
    end

    test "rejects missing, dead, and unflagged metadata", %{banker_guid: banker_guid, state: state} do
      Metadata.delete(banker_guid)
      refute Bank.valid_banker?(state.character, banker_guid)

      Metadata.put(banker_guid, %{npc_flags: @banker_flag, alive?: false})
      refute Bank.valid_banker?(state.character, banker_guid)

      Metadata.put(banker_guid, %{npc_flags: 0, alive?: true})
      refute Bank.valid_banker?(state.character, banker_guid)
    end

    test "rejects hostile bankers", %{banker_guid: banker_guid, state: state} do
      previous_catalog = ReputationLoader.catalog()
      catalog = %Catalog{factions: %{72 => %Definition{id: 72, index: 19, variants: [%Variant{}]}}}
      ReputationLoader.put_catalog(catalog)
      on_exit(fn -> ReputationLoader.put_catalog(previous_catalog) end)

      reputation = ReputationLogic.initialize(catalog, 1, 1)
      {reputation, _changes} = ReputationLogic.set(reputation, catalog, 72, -6_000, %{race: 1, class: 1})
      character = %{state.character | player: %{state.character.player | reputation: reputation}}
      Metadata.update(banker_guid, %{faction_template: %FactionTemplate{faction: 72}})

      refute Bank.valid_banker?(character, banker_guid)
    end

    test "rejects a banker in another world or beyond five yards", %{banker_guid: banker_guid, state: state} do
      SpatialHash.update(:mobs, banker_guid, WorldRef.open(1), 2.0, 0.0, 0.0)
      refute Bank.valid_banker?(state.character, banker_guid)

      SpatialHash.update(:mobs, banker_guid, WorldRef.open(0), 5.01, 0.0, 0.0)
      refute Bank.valid_banker?(state.character, banker_guid)
    end

    test "requires a ready living character", %{banker_guid: banker_guid, state: state} do
      refute Bank.activate(%{state | ready: false}, banker_guid).active_banker_guid

      dead = %{state.character | unit: %{state.character.unit | health: 0}}
      refute Bank.activate(%{state | character: dead}, banker_guid).active_banker_guid
    end
  end

  describe "authorize/1" do
    test "invalidates a stale capability after movement and metadata changes", %{banker_guid: banker_guid, state: state} do
      state = Bank.activate(state, banker_guid)
      SpatialHash.update(:mobs, banker_guid, WorldRef.open(0), 6.0, 0.0, 0.0)

      assert {:error, state} = Bank.authorize(state)
      assert state.active_banker_guid == nil

      SpatialHash.update(:mobs, banker_guid, WorldRef.open(0), 2.0, 0.0, 0.0)
      state = Bank.activate(state, banker_guid)
      Metadata.update(banker_guid, %{alive?: false})

      assert {:error, state} = Bank.authorize(state)
      assert state.active_banker_guid == nil
    end

    test "worldport and leave-world transitions clear the capability", %{banker_guid: banker_guid, state: state} do
      active = %{state | active_banker_guid: banker_guid}
      worldported = State.prepare_worldport(active, WorldRef.open(0), WorldRef.open(1))
      assert worldported.active_banker_guid == nil

      left = State.leave_world(%State{account: 1, connection_pid: self(), active_banker_guid: banker_guid})
      assert left.active_banker_guid == nil
    end
  end

  describe "generic inventory authorization" do
    test "rejects remote bank swaps and allows them through a valid session", %{banker_guid: banker_guid, state: state} do
      item = ItemStore.create(%ItemTemplate{entry: 20_000}, owner: state.guid)
      state = put_in(state.character.player.inv1, item.object.guid)

      rejected = PlayerInventory.swap(state, {@bag_0, @backpack_start}, {@bag_0, @bank_start})
      assert rejected.character.player.inv1 == item.object.guid
      assert rejected.character.player.bank1 in [nil, 0]

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 35}}}

      accepted =
        state |> Bank.activate(banker_guid) |> PlayerInventory.swap({@bag_0, @backpack_start}, {@bag_0, @bank_start})

      assert accepted.character.player.inv1 == 0
      assert accepted.character.player.bank1 == item.object.guid
      assert CharacterStore.get(accepted.character.id).player.bank1 == item.object.guid

      assert %{condition_subject: subject} = Metadata.get(accepted.guid)
      assert subject.item_counts == %{20_000 => 0}
      assert subject.item_counts_with_bank == %{20_000 => 1}

      withdrawn = Bank.auto_store_bank(accepted, {@bag_0, @bank_start})
      assert withdrawn.character.player.inv1 == item.object.guid
      assert withdrawn.character.player.bank1 == 0

      assert %{condition_subject: subject} = Metadata.get(withdrawn.guid)
      assert subject.item_counts == %{20_000 => 1}
      assert subject.item_counts_with_bank == %{20_000 => 1}
    end

    test "rejects remote bank splits and destruction", %{state: state} do
      stack = ItemStore.create(%ItemTemplate{entry: 20_000, stackable: 10}, owner: state.guid, stack_count: 5)
      state = put_in(state.character.player.bank1, stack.object.guid)

      split = PlayerInventory.split(state, {@bag_0, @bank_start}, {@bag_0, @bank_start + 1}, 2)
      assert split.character.player.bank1 == stack.object.guid
      assert split.character.player.bank2 in [nil, 0]
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 35}}}

      destroyed = PlayerInventory.destroy(state, {@bag_0, @bank_start})
      assert destroyed.character.player.bank1 == stack.object.guid
      assert ItemStore.get(stack.object.guid) == stack
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 35}}}
    end
  end

  describe "buy_slot/3" do
    test "charges all six configured prices exactly once", %{banker_guid: banker_guid, state: state} do
      prices = %{1 => 1_000, 2 => 10_000, 3 => 100_000, 4 => 250_000, 5 => 500_000, 6 => 1_000_000}
      state = put_in(state.character.player.coinage, 2_000_000)

      state =
        Enum.reduce(1..6, state, fn expected_slots, state ->
          state = Bank.buy_slot(state, banker_guid, price_lookup: &Map.get(prices, &1))
          assert state.character.player.bank_bag_slots == expected_slots
          state
        end)

      assert state.character.player.coinage == 139_000
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgBuyBankSlotResult{}}}
    end

    test "reports insufficient funds without charging", %{banker_guid: banker_guid, state: state} do
      state = put_in(state.character.player.coinage, 999)
      result = Bank.buy_slot(state, banker_guid, price_lookup: fn 1 -> 1_000 end)

      assert result.character.player.coinage == 999
      assert result.character.player.bank_bag_slots == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyBankSlotResult{result: 1}}}
    end

    test "reports the client maximum without charging", %{banker_guid: banker_guid, state: state} do
      state = put_in(state.character.player.bank_bag_slots, 6)
      result = Bank.buy_slot(state, banker_guid, price_lookup: fn _slot -> nil end)

      assert result.character.player.coinage == state.character.player.coinage
      assert result.character.player.bank_bag_slots == 6
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyBankSlotResult{result: 0}}}
    end

    test "reports an invalid banker and clears the capability", %{state: state} do
      result = Bank.buy_slot(state, Guid.from_low_guid(:player, 99), price_lookup: fn _slot -> 1 end)

      assert result.active_banker_guid == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyBankSlotResult{result: 2}}}
    end
  end

  defp character(id) do
    %Character{
      id: id,
      account_id: 1,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      unit: %Unit{race: 1, class: 1, level: 10, health: 100},
      player: %Player{coinage: 100, bank_bag_slots: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end
end
