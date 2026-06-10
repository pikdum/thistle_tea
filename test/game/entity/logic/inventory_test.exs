defmodule ThistleTea.Game.Entity.Logic.InventoryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory

  @bag_0 255
  @mainhand_slot 15
  @offhand_slot 16
  @first_bag_slot 19
  @backpack_start 23
  @owner 1

  setup [:build_fixtures]

  defp build_fixtures(_context) do
    warrior = %Unit{class: 1, race: 1, level: 10}

    {:ok,
     unit: warrior,
     chest: build_item(1, %ItemTemplate{entry: 100, inventory_type: 5}),
     sword: build_item(2, %ItemTemplate{entry: 200, inventory_type: 13}),
     greatsword: build_item(3, %ItemTemplate{entry: 300, inventory_type: 17}),
     shield: build_item(4, %ItemTemplate{entry: 400, inventory_type: 14}),
     ring: build_item(5, %ItemTemplate{entry: 500, inventory_type: 11}),
     high_level: build_item(6, %ItemTemplate{entry: 600, inventory_type: 5, required_level: 60}),
     priest_only: build_item(7, %ItemTemplate{entry: 700, inventory_type: 5, allowable_class: 16}),
     bag: build_item(8, %ItemTemplate{entry: 800, inventory_type: 18, container_slots: 6, class: 1})}
  end

  defp build_item(low_guid, template, opts \\ []) do
    Item.build(template, 0x4000_0000_0000_0000 + low_guid, Keyword.merge([owner: @owner], opts))
  end

  defp get_item_fn(items) do
    by_guid = Map.new(items, fn item -> {item.object.guid, item} end)
    fn guid -> Map.get(by_guid, guid) end
  end

  defp store(player, slot, item) do
    Map.put(player, :"inv#{slot - @backpack_start + 1}", item.object.guid)
  end

  defp updated(items, %Item{} = item) do
    Enum.find(items, fn i -> i.object.guid == item.object.guid end)
  end

  describe "equip/3" do
    test "sets slot guid and visible entry", %{chest: chest} do
      player = Inventory.equip(%Player{}, :chest, chest)

      assert player.chest == chest.object.guid
      assert player.visible_item_5_0 == 100
    end
  end

  describe "auto_equip/5" do
    test "equips into the matching empty slot", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, @owner, {@bag_0, @backpack_start}, get_item_fn([chest]))

      assert player.chest == chest.object.guid
      assert player.visible_item_5_0 == 100
      assert player.inv1 == 0
    end

    test "swaps with the currently equipped item", %{unit: unit, chest: chest} do
      other_chest = build_item(9, %ItemTemplate{entry: 900, inventory_type: 5})

      player =
        %Player{}
        |> Inventory.equip(:chest, other_chest)
        |> store(@backpack_start, chest)

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, @owner, {@bag_0, @backpack_start}, get_item_fn([chest, other_chest]))

      assert player.chest == chest.object.guid
      assert player.inv1 == other_chest.object.guid
    end

    test "equips a bag into a free bag slot", %{unit: unit, bag: bag} do
      player = store(%Player{}, @backpack_start, bag)

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, @owner, {@bag_0, @backpack_start}, get_item_fn([bag]))

      assert player.bag1 == bag.object.guid
      assert player.inv1 == 0
    end

    test "rejects items above the player level", %{unit: unit, high_level: high_level} do
      player = store(%Player{}, @backpack_start, high_level)

      assert {:error, :cant_equip_level_i, guid, 0} =
               Inventory.auto_equip(player, unit, @owner, {@bag_0, @backpack_start}, get_item_fn([high_level]))

      assert guid == high_level.object.guid
    end

    test "rejects items for other classes", %{unit: unit, priest_only: priest_only} do
      player = store(%Player{}, @backpack_start, priest_only)

      assert {:error, :you_can_never_use_that_item, _, 0} =
               Inventory.auto_equip(player, unit, @owner, {@bag_0, @backpack_start}, get_item_fn([priest_only]))
    end
  end

  describe "swap/6" do
    test "swaps two backpack slots", %{unit: unit, chest: chest, sword: sword} do
      player =
        %Player{}
        |> store(@backpack_start, chest)
        |> store(@backpack_start + 1, sword)

      assert {:ok, %{player: player}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 get_item_fn([chest, sword])
               )

      assert player.inv1 == sword.object.guid
      assert player.inv2 == chest.object.guid
    end

    test "moves an item into an equipped bag", %{unit: unit, chest: chest, bag: bag} do
      player =
        %Player{}
        |> Map.put(:bag1, bag.object.guid)
        |> store(@backpack_start, chest)

      assert {:ok, %{player: player, items: items}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@first_bag_slot, 0},
                 get_item_fn([chest, bag])
               )

      assert player.inv1 == 0
      assert updated(items, bag).container.slot_1 == chest.object.guid
      assert updated(items, chest).item.contained == bag.object.guid
    end

    test "moves an item back out of a bag", %{unit: unit, chest: chest, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: chest.object.guid}}
      chest = %{chest | item: %{chest.item | contained: bag.object.guid}}
      player = Map.put(%Player{}, :bag1, bag.object.guid)

      assert {:ok, %{player: player, items: items}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@first_bag_slot, 0},
                 {@bag_0, @backpack_start},
                 get_item_fn([chest, bag])
               )

      assert player.inv1 == chest.object.guid
      assert updated(items, bag).container.slot_1 == 0
      assert updated(items, chest).item.contained == @owner
    end

    test "rejects moving a non-empty bag off the bag bar", %{unit: unit, chest: chest, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: chest.object.guid}}
      player = Map.put(%Player{}, :bag1, bag.object.guid)

      assert {:error, :can_only_do_with_empty_bags, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @first_bag_slot},
                 {@bag_0, @backpack_start},
                 get_item_fn([chest, bag])
               )
    end

    test "rejects putting a bag inside itself", %{unit: unit, bag: bag} do
      player = Map.put(%Player{}, :bag1, bag.object.guid)

      assert {:error, :items_cant_be_swapped, _, _} =
               Inventory.swap(player, unit, @owner, {@bag_0, @first_bag_slot}, {@first_bag_slot, 0}, get_item_fn([bag]))
    end

    test "rejects non-bags in bag slots", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:error, :not_a_bag, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @first_bag_slot},
                 get_item_fn([chest])
               )
    end

    test "rejects equipping into the wrong slot", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:error, :item_doesnt_go_to_slot, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @mainhand_slot},
                 get_item_fn([chest])
               )
    end

    test "rejects offhand while a two-hander is equipped", %{unit: unit, greatsword: greatsword, shield: shield} do
      player =
        %Player{}
        |> Inventory.equip(:mainhand, greatsword)
        |> store(@backpack_start, shield)

      assert {:error, :cant_equip_with_twohanded, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @offhand_slot},
                 get_item_fn([greatsword, shield])
               )
    end

    test "stores the offhand when equipping a two-hander", %{
      unit: unit,
      greatsword: greatsword,
      shield: shield,
      sword: sword
    } do
      player =
        %Player{}
        |> Inventory.equip(:mainhand, sword)
        |> Inventory.equip(:offhand, shield)
        |> store(@backpack_start, greatsword)

      assert {:ok, %{player: player}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @mainhand_slot},
                 get_item_fn([greatsword, shield, sword])
               )

      assert player.mainhand == greatsword.object.guid
      assert player.offhand == 0
      assert player.visible_item_17_0 == 0
      assert player.inv1 == sword.object.guid
      assert player.inv2 == shield.object.guid
    end
  end

  describe "store/4" do
    test "uses the first free backpack slot", %{chest: chest} do
      assert {:ok, %{player: player}, {:placed, {@bag_0, @backpack_start}, placed}} =
               Inventory.store(%Player{}, @owner, chest, get_item_fn([chest]))

      assert player.inv1 == chest.object.guid
      assert placed.object.guid == chest.object.guid
    end

    test "overflows into an equipped bag when the backpack is full", %{chest: chest, bag: bag} do
      filler = build_item(10, %ItemTemplate{entry: 1000})

      player =
        Enum.reduce(0..15, Map.put(%Player{}, :bag1, bag.object.guid), fn i, p ->
          store(p, @backpack_start + i, filler)
        end)

      assert {:ok, %{items: items}, {:placed, {@first_bag_slot, 0}, placed}} =
               Inventory.store(player, @owner, chest, get_item_fn([chest, bag, filler]))

      assert updated(items, bag).container.slot_1 == chest.object.guid
      assert placed.item.contained == bag.object.guid
    end

    test "fails when everything is full", %{chest: chest} do
      filler = build_item(10, %ItemTemplate{entry: 1000})
      player = Enum.reduce(0..15, %Player{}, fn i, p -> store(p, @backpack_start + i, filler) end)

      assert {:error, :inventory_full} = Inventory.store(player, @owner, chest, get_item_fn([chest, filler]))
    end

    test "merges fully into an existing stack" do
      stack = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 4)
      incoming = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      player = store(%Player{}, @backpack_start, stack)

      assert {:ok, %{items: items}, :merged} =
               Inventory.store(player, @owner, incoming, get_item_fn([stack, incoming]))

      assert updated(items, stack).item.stack_count == 7
    end

    test "fills a stack and places the remainder" do
      stack = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 8)
      incoming = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 5)
      player = store(%Player{}, @backpack_start, stack)

      assert {:ok, %{items: items}, {:placed, pos, placed}} =
               Inventory.store(player, @owner, incoming, get_item_fn([stack, incoming]))

      assert pos == {@bag_0, @backpack_start + 1}
      assert updated(items, stack).item.stack_count == 10
      assert placed.item.stack_count == 3
    end
  end

  describe "swap/6 stacking" do
    test "merges a stack dropped onto a matching stack", %{unit: unit} do
      src = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      dst = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 4)

      player =
        %Player{}
        |> store(@backpack_start, src)
        |> store(@backpack_start + 1, dst)

      assert {:ok, %{player: player, items: items, destroyed: [destroyed]}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 get_item_fn([src, dst])
               )

      assert player.inv1 == 0
      assert updated(items, dst).item.stack_count == 7
      assert destroyed.object.guid == src.object.guid
    end

    test "partially fills a nearly full stack", %{unit: unit} do
      src = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 5)
      dst = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 8)

      player =
        %Player{}
        |> store(@backpack_start, src)
        |> store(@backpack_start + 1, dst)

      assert {:ok, %{player: player, items: items, destroyed: []}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 get_item_fn([src, dst])
               )

      assert player.inv1 == src.object.guid
      assert updated(items, src).item.stack_count == 3
      assert updated(items, dst).item.stack_count == 10
    end

    test "swaps positions when the target stack is full", %{unit: unit} do
      src = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 5)
      dst = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 10)

      player =
        %Player{}
        |> store(@backpack_start, src)
        |> store(@backpack_start + 1, dst)

      assert {:ok, %{player: player}} =
               Inventory.swap(
                 player,
                 unit,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 get_item_fn([src, dst])
               )

      assert player.inv1 == dst.object.guid
      assert player.inv2 == src.object.guid
    end
  end

  describe "split/6" do
    test "splits a stack into an empty slot" do
      src = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 8)
      new_item = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      player = store(%Player{}, @backpack_start, src)

      assert {:ok, %{player: player, items: items}, placed} =
               Inventory.split(
                 player,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 new_item,
                 get_item_fn([src])
               )

      assert player.inv2 == new_item.object.guid
      assert updated(items, src).item.stack_count == 5
      assert placed.item.stack_count == 3
    end

    test "rejects splitting the whole stack" do
      src = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      new_item = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      player = store(%Player{}, @backpack_start, src)

      assert {:error, :tried_to_split_more_than_count, _, 0} =
               Inventory.split(
                 player,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 new_item,
                 get_item_fn([src])
               )
    end

    test "rejects splitting onto an occupied slot", %{chest: chest} do
      src = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 8)
      new_item = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)

      player =
        %Player{}
        |> store(@backpack_start, src)
        |> store(@backpack_start + 1, chest)

      assert {:error, :couldnt_split_items, _, 0} =
               Inventory.split(
                 player,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @backpack_start + 1},
                 new_item,
                 get_item_fn([src, chest])
               )
    end
  end

  describe "destroy/3" do
    test "clears the slot and returns the item", %{chest: chest} do
      player = Inventory.equip(%Player{}, :chest, chest)

      assert {:ok, %{player: player}, item} = Inventory.destroy(player, {@bag_0, 4}, get_item_fn([chest]))
      assert item == chest
      assert player.chest == 0
      assert player.visible_item_5_0 == 0
    end

    test "destroys items inside bags", %{chest: chest, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: chest.object.guid}}
      player = Map.put(%Player{}, :bag1, bag.object.guid)

      assert {:ok, %{items: items}, item} =
               Inventory.destroy(player, {@first_bag_slot, 0}, get_item_fn([chest, bag]))

      assert item.object.guid == chest.object.guid
      assert updated(items, bag).container.slot_1 == 0
    end

    test "rejects destroying a non-empty bag", %{chest: chest, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: chest.object.guid}}
      player = Map.put(%Player{}, :bag1, bag.object.guid)

      assert {:error, :can_only_do_with_empty_bags, _, 0} =
               Inventory.destroy(player, {@bag_0, @first_bag_slot}, get_item_fn([chest, bag]))
    end

    test "rejects empty slots" do
      assert {:error, :item_not_found, 0, 0} = Inventory.destroy(%Player{}, {@bag_0, 4}, fn _ -> nil end)
    end
  end

  describe "find_position/3" do
    test "finds items in equipment, backpack, and bags", %{chest: chest, sword: sword, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_3: sword.object.guid}}

      player =
        %Player{}
        |> Inventory.equip(:chest, chest)
        |> Map.put(:bag1, bag.object.guid)

      get_item = get_item_fn([chest, sword, bag])

      assert Inventory.find_position(player, chest.object.guid, get_item) == {@bag_0, 4}
      assert Inventory.find_position(player, bag.object.guid, get_item) == {@bag_0, @first_bag_slot}
      assert Inventory.find_position(player, sword.object.guid, get_item) == {@first_bag_slot, 2}
      assert Inventory.find_position(player, 999, get_item) == nil
    end
  end

  describe "reduce_stack/4" do
    test "reduces a stack in place" do
      stack = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 8)
      player = store(%Player{}, @backpack_start, stack)

      assert {:ok, %{items: items}} =
               Inventory.reduce_stack(player, {@bag_0, @backpack_start}, 3, get_item_fn([stack]))

      assert updated(items, stack).item.stack_count == 5
    end

    test "rejects reducing by the full count" do
      stack = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      player = store(%Player{}, @backpack_start, stack)

      assert {:error, :item_not_found, _, 0} =
               Inventory.reduce_stack(player, {@bag_0, @backpack_start}, 3, get_item_fn([stack]))
    end
  end

  describe "owned_items/2" do
    test "includes equipment, backpack, bags, and bag contents", %{chest: chest, sword: sword, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: sword.object.guid}}

      player =
        %Player{}
        |> Inventory.equip(:chest, chest)
        |> Map.put(:bag1, bag.object.guid)

      guids =
        player
        |> Inventory.owned_items(get_item_fn([chest, sword, bag]))
        |> Enum.map(& &1.object.guid)

      assert chest.object.guid in guids
      assert bag.object.guid in guids
      assert sword.object.guid in guids
    end
  end
end
