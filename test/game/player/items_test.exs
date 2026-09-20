defmodule ThistleTea.Game.Player.ItemsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @entry 987_950

  setup [:inventory]

  describe "create/3" do
    test "silently preserves an existing unique item in the bank", %{state: state} do
      template = %ItemTemplate{entry: @entry, max_count: 1}
      :ets.insert(ItemLoader, {@entry, template})
      existing = ItemStore.create(template, owner: state.guid)
      state = put_in(state.character.player.bank1, existing.object.guid)
      size = :ets.info(ItemStore, :size)

      assert Items.create(state, @entry, 1) == state
      assert :ets.info(ItemStore, :size) == size
      refute_received {:"$gen_cast", {:send_packet, _}}
    end

    test "replaces a missing unique item once", %{state: state} do
      :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, max_count: 1}})
      created = Items.create(state, @entry, 1)
      assert Inventory.count_entry(created.character.player, @entry, &ItemStore.get/1) == 1
      assert Items.create(created, @entry, 1) == created
    end

    test "clamps spell-created stacks to the remaining unique allowance", %{state: state} do
      template = %ItemTemplate{entry: @entry, max_count: 5, stackable: 20}
      :ets.insert(ItemLoader, {@entry, template})
      existing = ItemStore.create(template, owner: state.guid, stack_count: 3)
      state = put_in(state.character.player.inv1, existing.object.guid)
      created = Items.create(state, @entry, 4)
      assert Inventory.count_entry(created.character.player, @entry, &ItemStore.get/1) == 5
    end
  end

  describe "store/3" do
    test "creates separate instances of non-stackable equipment", %{state: state} do
      assert {:ok, stored, {255, 23}} = Items.store(state, @entry, 2)
      items = Inventory.owned_items(stored.character.player, &ItemStore.get/1)
      assert Enum.map(items, & &1.item.stack_count) == [1, 1]
      assert length(Enum.uniq_by(items, & &1.object.guid)) == 2
    end

    test "splits large grants into legal stacks", %{state: state} do
      :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, stackable: 20}})
      assert {:ok, stored, _position} = Items.store(state, @entry, 45)

      assert Inventory.owned_items(stored.character.player, &ItemStore.get/1) |> Enum.map(& &1.item.stack_count) == [
               20,
               20,
               5
             ]
    end

    test "rolls back the entire grant when all instances cannot fit", %{state: state} do
      player =
        Enum.reduce(1..15, state.character.player, fn slot, player ->
          item = ItemStore.create(%ItemTemplate{entry: @entry + 1}, owner: state.guid)
          Map.replace!(player, :"inv#{slot}", item.object.guid)
        end)

      state = %{state | character: %{state.character | player: player}}
      size = :ets.info(ItemStore, :size)
      assert {:error, :inventory_full, ^state} = Items.store(state, @entry, 2)
      assert :ets.info(ItemStore, :size) == size
      assert Inventory.count_entry(player, @entry, &ItemStore.get/1) == 0
    end
  end

  defp inventory(_context) do
    ItemStore.init()
    ItemLoader.init()
    :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, stackable: 1}})

    character =
      CharacterStore.create(%Character{
        id: 0,
        object: %Object{guid: 0},
        player: %Player{},
        unit: %Unit{health: 100, max_health: 100, level: 10},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{}
      })

    guid = character.object.guid

    on_exit(fn ->
      :ets.delete(ItemLoader, @entry)
      :ets.delete(CharacterStore, character.id)

      :ets.select_delete(ItemStore, [{{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, guid}], [true]}])
    end)

    %{state: %State{guid: guid, character: character}}
  end
end
