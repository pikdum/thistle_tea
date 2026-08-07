defmodule ThistleTea.Game.Entity.Logic.InventoryTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Entity.Logic.Proficiency

  @bag_0 255
  @mainhand_slot 15
  @offhand_slot 16
  @first_bag_slot 19
  @backpack_start 23
  @bank_start 39
  @bank_bag_start 63
  @owner 1
  @prof Proficiency.all()

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

  defp get_item_after(result, get_item) do
    changed = Map.new(result.items, fn item -> {item.object.guid, item} end)
    destroyed = MapSet.new(result.destroyed, fn item -> item.object.guid end)

    fn guid ->
      cond do
        MapSet.member?(destroyed, guid) -> nil
        Map.has_key?(changed, guid) -> Map.get(changed, guid)
        true -> get_item.(guid)
      end
    end
  end

  defp store(player, slot, item) do
    Map.put(player, :"inv#{slot - @backpack_start + 1}", item.object.guid)
  end

  defp store_bank(player, slot, item) do
    Map.put(player, :"bank#{slot - @bank_start + 1}", item.object.guid)
  end

  defp updated(items, %Item{} = item) do
    Enum.find(items, fn i -> i.object.guid == item.object.guid end)
  end

  describe "count_entry/3" do
    test "sums stacks across backpack and bag contents" do
      pelt_template = %ItemTemplate{entry: 750, stackable: 10}
      pelt1 = build_item(20, pelt_template, stack_count: 3)
      pelt2 = build_item(21, pelt_template, stack_count: 2)
      bag = build_item(22, %ItemTemplate{entry: 800, inventory_type: 18, container_slots: 6, class: 1})
      bag = put_in(bag.container.slot_1, pelt2.object.guid)

      player =
        %Player{}
        |> store(@backpack_start, pelt1)
        |> Map.put(:bag1, bag.object.guid)

      get_item = get_item_fn([pelt1, pelt2, bag])

      assert Inventory.count_entry(player, 750, get_item) == 5
      assert Inventory.count_entry(player, 999, get_item) == 0
    end
  end

  describe "remove_count/4" do
    test "reduces a stack partially" do
      pelt = build_item(20, %ItemTemplate{entry: 750, stackable: 10}, stack_count: 5)
      player = store(%Player{}, @backpack_start, pelt)
      get_item = get_item_fn([pelt])

      assert {:ok, result} = Inventory.remove_count(player, 750, 3, get_item)
      assert [updated_pelt] = result.items
      assert updated_pelt.item.stack_count == 2
      assert result.destroyed == []
    end

    test "destroys whole stacks and spills into the next" do
      pelt1 = build_item(20, %ItemTemplate{entry: 750, stackable: 10}, stack_count: 4)
      pelt2 = build_item(21, %ItemTemplate{entry: 750, stackable: 10}, stack_count: 4)

      player =
        %Player{}
        |> store(@backpack_start, pelt1)
        |> store(@backpack_start + 1, pelt2)

      get_item = get_item_fn([pelt1, pelt2])

      assert {:ok, result} = Inventory.remove_count(player, 750, 6, get_item)
      assert length(result.destroyed) == 1
      assert [updated] = result.items
      assert updated.item.stack_count == 2
      assert Inventory.count_entry(result.player, 750, get_item_after(result, get_item)) == 2
    end

    test "errors when there are not enough items" do
      pelt = build_item(20, %ItemTemplate{entry: 750, stackable: 10}, stack_count: 2)
      player = store(%Player{}, @backpack_start, pelt)

      assert {:error, :item_not_found, 0, 0} =
               Inventory.remove_count(player, 750, 5, get_item_fn([pelt]))
    end
  end

  describe "plan/2" do
    test "uses slots freed by removals for additions" do
      required = build_item(20, %ItemTemplate{entry: 750})
      reward = build_item(40, %ItemTemplate{entry: 900})
      fillers = Enum.map(21..35, &build_item(&1, %ItemTemplate{entry: 800 + &1}))

      player =
        [required | fillers]
        |> Enum.with_index(@backpack_start)
        |> Enum.reduce(%Player{}, fn {item, slot}, player -> store(player, slot, item) end)

      get_item = get_item_fn([required, reward | fillers])

      batch =
        player
        |> Batch.new()
        |> Batch.remove(750, 1)
        |> Batch.add(reward)

      assert {:ok, %ChangeSet{} = change_set} = Inventory.plan(batch, get_item)
      assert change_set.player.inv1 == reward.object.guid
      assert [^required] = ChangeSet.destroyed_items(change_set)

      assert %Placement{status: :placed, position: {@bag_0, @backpack_start}} =
               ChangeSet.placement(change_set, reward.object.guid)

      assert player.inv1 == required.object.guid
    end

    test "rejects additions that only fit when checked independently" do
      fillers = Enum.map(20..34, &build_item(&1, %ItemTemplate{entry: 800 + &1}))
      reward1 = build_item(40, %ItemTemplate{entry: 900})
      reward2 = build_item(41, %ItemTemplate{entry: 901})

      player =
        fillers
        |> Enum.with_index(@backpack_start)
        |> Enum.reduce(%Player{}, fn {item, slot}, player -> store(player, slot, item) end)

      batch = player |> Batch.new() |> Batch.add(reward1) |> Batch.add(reward2)

      get_item = get_item_fn([reward1, reward2 | fillers])

      assert {:error, :inventory_full} = Inventory.plan(batch, get_item)
      assert Inventory.item_guid_at(player, {@bag_0, @backpack_start + 15}, get_item) == nil
    end

    test "later additions see earlier placements and merge into them" do
      template = %ItemTemplate{entry: 900, stackable: 20}
      reward1 = build_item(40, template, stack_count: 4)
      reward2 = build_item(41, template, stack_count: 3)
      batch = %Player{} |> Batch.new() |> Batch.add(reward1) |> Batch.add(reward2)

      assert {:ok, %ChangeSet{} = change_set} =
               Inventory.plan(batch, get_item_fn([reward1, reward2]))

      assert [placed] = ChangeSet.placed_items(change_set)
      assert placed.object.guid == reward1.object.guid
      assert placed.item.stack_count == 7

      assert [
               %Placement{status: :placed},
               %Placement{status: :merged}
             ] = change_set.placements
    end

    test "returns no partial change set when a removal cannot be satisfied" do
      required = build_item(20, %ItemTemplate{entry: 750})
      reward = build_item(40, %ItemTemplate{entry: 900})
      player = store(%Player{}, @backpack_start, required)
      batch = player |> Batch.new() |> Batch.remove(750, 2) |> Batch.add(reward)

      assert {:error, :item_not_found} =
               Inventory.plan(batch, get_item_fn([required, reward]))

      assert player.inv1 == required.object.guid
    end
  end

  describe "equip/3" do
    test "sets slot guid and visible entry", %{chest: chest} do
      player = Inventory.equip(%Player{}, :chest, chest)

      assert player.chest == chest.object.guid
      assert player.visible_item_5_0 == 100
    end
  end

  describe "auto_equip/6" do
    test "equips into the matching empty slot", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, @prof, @owner, {@bag_0, @backpack_start}, get_item_fn([chest]))

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

      get_item = get_item_fn([chest, other_chest])

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, @prof, @owner, {@bag_0, @backpack_start}, get_item)

      assert player.chest == chest.object.guid
      assert player.inv1 == other_chest.object.guid
    end

    test "equips a bag into a free bag slot", %{unit: unit, bag: bag} do
      player = store(%Player{}, @backpack_start, bag)

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, @prof, @owner, {@bag_0, @backpack_start}, get_item_fn([bag]))

      assert player.bag1 == bag.object.guid
      assert player.inv1 == 0
    end

    test "rejects items above the player level", %{unit: unit, high_level: high_level} do
      player = store(%Player{}, @backpack_start, high_level)

      assert {:error, :cant_equip_level_i, guid, 0} =
               Inventory.auto_equip(player, unit, @prof, @owner, {@bag_0, @backpack_start}, get_item_fn([high_level]))

      assert guid == high_level.object.guid
    end

    test "rejects items for other classes", %{unit: unit, priest_only: priest_only} do
      player = store(%Player{}, @backpack_start, priest_only)

      assert {:error, :you_can_never_use_that_item, _, 0} =
               Inventory.auto_equip(player, unit, @prof, @owner, {@bag_0, @backpack_start}, get_item_fn([priest_only]))
    end

    test "applies an injected item-use requirement", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:error, :cant_equip_reputation, guid, 0} =
               Inventory.auto_equip(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @backpack_start},
                 get_item_fn([chest]),
                 validate_item: fn _template -> {:error, :cant_equip_reputation} end
               )

      assert guid == chest.object.guid
      assert Inventory.error_code(:cant_equip_reputation) == 64
    end

    test "rejects weapons without the matching proficiency", %{unit: unit} do
      dagger = build_item(11, %ItemTemplate{entry: 1100, inventory_type: 13, class: 2, subclass: 15})
      player = store(%Player{}, @backpack_start, dagger)
      staves_only = %Proficiency{weapon_mask: 1 <<< 10}

      assert {:error, :no_required_proficiency, _, 0} =
               Inventory.auto_equip(player, unit, staves_only, @owner, {@bag_0, @backpack_start}, get_item_fn([dagger]))
    end

    test "rejects armor without the matching proficiency", %{unit: unit} do
      leather_chest = build_item(12, %ItemTemplate{entry: 1200, inventory_type: 5, class: 4, subclass: 2})
      player = store(%Player{}, @backpack_start, leather_chest)
      cloth_only = %Proficiency{armor_mask: 1 <<< 1}

      assert {:error, :no_required_proficiency, _, 0} =
               Inventory.auto_equip(
                 player,
                 unit,
                 cloth_only,
                 @owner,
                 {@bag_0, @backpack_start},
                 get_item_fn([leather_chest])
               )
    end

    test "equips weapons and armor with the matching proficiency", %{unit: unit} do
      staff = build_item(13, %ItemTemplate{entry: 1300, inventory_type: 17, class: 2, subclass: 10})
      player = store(%Player{}, @backpack_start, staff)
      prof = %Proficiency{weapon_mask: 1 <<< 10}

      assert {:ok, %{player: player}} =
               Inventory.auto_equip(player, unit, prof, @owner, {@bag_0, @backpack_start}, get_item_fn([staff]))

      assert player.mainhand == staff.object.guid
    end

    test "auto-equips a second one-hander into the offhand only with dual wield", %{unit: unit, sword: sword} do
      second = build_item(14, %ItemTemplate{entry: 1400, inventory_type: 13})

      player =
        %Player{}
        |> Inventory.equip(:mainhand, sword)
        |> store(@backpack_start, second)

      get_item = get_item_fn([sword, second])

      assert {:ok, %{player: with_dw}} =
               Inventory.auto_equip(player, unit, @prof, @owner, {@bag_0, @backpack_start}, get_item)

      assert with_dw.offhand == second.object.guid

      assert {:ok, %{player: without_dw}} =
               Inventory.auto_equip(
                 player,
                 unit,
                 %Proficiency{},
                 @owner,
                 {@bag_0, @backpack_start},
                 get_item
               )

      assert without_dw.mainhand == second.object.guid
      assert without_dw.offhand in [nil, 0]
    end
  end

  describe "swap/7" do
    test "swaps two backpack slots", %{unit: unit, chest: chest, sword: sword} do
      player =
        %Player{}
        |> store(@backpack_start, chest)
        |> store(@backpack_start + 1, sword)

      assert {:ok, %{player: player}} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
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
                 @prof,
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
      player = %Player{bag1: bag.object.guid}

      assert {:ok, %{player: player, items: items}} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
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
      player = %Player{bag1: bag.object.guid}

      assert {:error, :can_only_do_with_empty_bags, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @first_bag_slot},
                 {@bag_0, @backpack_start},
                 get_item_fn([chest, bag])
               )
    end

    test "rejects putting a bag inside itself", %{unit: unit, bag: bag} do
      player = %Player{bag1: bag.object.guid}

      assert {:error, :items_cant_be_swapped, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @first_bag_slot},
                 {@first_bag_slot, 0},
                 get_item_fn([bag])
               )
    end

    test "rejects non-bags in bag slots", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:error, :not_a_bag, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
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
                 @prof,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @mainhand_slot},
                 get_item_fn([chest])
               )
    end

    test "rejects placing a one-hander into the offhand without dual wield", %{unit: unit, sword: sword} do
      player = store(%Player{}, @backpack_start, sword)

      assert {:error, :cant_dual_wield, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 %Proficiency{},
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @offhand_slot},
                 get_item_fn([sword])
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
                 @prof,
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
                 @prof,
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
        Enum.reduce(0..15, %Player{bag1: bag.object.guid}, fn i, p ->
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

  describe "swap/7 stacking" do
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
                 @prof,
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
                 @prof,
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
                 @prof,
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
      player = %Player{bag1: bag.object.guid}

      assert {:ok, %{items: items}, item} =
               Inventory.destroy(player, {@first_bag_slot, 0}, get_item_fn([chest, bag]))

      assert item.object.guid == chest.object.guid
      assert updated(items, bag).container.slot_1 == 0
    end

    test "rejects destroying a non-empty bag", %{chest: chest, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: chest.object.guid}}
      player = %Player{bag1: bag.object.guid}

      assert {:error, :can_only_do_with_empty_bags, _, 0} =
               Inventory.destroy(player, {@bag_0, @first_bag_slot}, get_item_fn([chest, bag]))
    end

    test "rejects empty slots" do
      assert {:error, :item_not_found, 0, 0} = Inventory.destroy(%Player{}, {@bag_0, 4}, fn _ -> nil end)
    end
  end

  describe "detach/3" do
    test "removes an item without destroying it", %{chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:ok, %{player: player, destroyed: []}, item} =
               Inventory.detach(player, {@bag_0, @backpack_start}, get_item_fn([chest]))

      assert player.inv1 == 0
      assert item == chest
    end

    test "rejects a non-empty bag", %{chest: chest, bag: bag} do
      bag = %{bag | container: %{bag.container | slot_1: chest.object.guid}}
      player = %Player{bag1: bag.object.guid}

      assert {:error, :can_only_do_with_empty_bags, _, 0} =
               Inventory.detach(player, {@bag_0, @first_bag_slot}, get_item_fn([chest, bag]))
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

  describe "bank storage catalog" do
    test "maps every vanilla bank region through the canonical slot catalog" do
      assert Inventory.field_for_position({@bag_0, @bank_start}) == :bank1
      assert Inventory.field_for_position({@bag_0, @bank_start + 23}) == :bank24
      assert Inventory.field_for_position({@bag_0, @bank_bag_start}) == :bank_bag1
      assert Inventory.field_for_position({@bag_0, @bank_bag_start + 5}) == :bank_bag6
      assert Inventory.field_for_position({@bag_0, 69}) == nil
    end

    test "classifies carried, bank, and purchased bank bag positions" do
      player = %Player{bank_bag_slots: 1}

      assert Inventory.carried_position?({@bag_0, @backpack_start})
      assert Inventory.carried_position?({@first_bag_slot, 0})
      refute Inventory.carried_position?({@bag_0, @bank_start})

      assert Inventory.bank_position?({@bag_0, @bank_start})
      assert Inventory.bank_position?({@bank_bag_start, 0})
      assert Inventory.bank_bag_bar_position?({@bag_0, @bank_bag_start})
      assert Inventory.purchased_bank_bag_position?(player, {@bag_0, @bank_bag_start})
      assert Inventory.purchased_bank_bag_position?(player, {@bank_bag_start, 0})
      refute Inventory.purchased_bank_bag_position?(player, {@bag_0, @bank_bag_start + 1})
      assert Inventory.touches_bank?([{@bag_0, @backpack_start}, {@bag_0, @bank_start}])
    end

    test "rejects locked bank bag slots", %{unit: unit, bag: bag} do
      player = store(%Player{}, @backpack_start, bag)

      assert {:error, :must_purchase_that_bag_slot, _, 0} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @bank_bag_start},
                 get_item_fn([bag])
               )
    end
  end

  describe "bank item enumeration" do
    test "keeps carried, bank, and all-owned scopes distinct" do
      carried = build_item(20, %ItemTemplate{entry: 2000})
      banked = build_item(21, %ItemTemplate{entry: 2001})
      contained = build_item(22, %ItemTemplate{entry: 2002})
      bank_bag = build_item(23, %ItemTemplate{entry: 2003, inventory_type: 18, container_slots: 6, class: 1})
      bank_bag = put_in(bank_bag.container.slot_1, contained.object.guid)

      player = %Player{
        inv1: carried.object.guid,
        bank1: banked.object.guid,
        bank_bag1: bank_bag.object.guid,
        bank_bag_slots: 1
      }

      lookup = get_item_fn([carried, banked, contained, bank_bag])

      assert Enum.map(Inventory.owned_items(player, lookup), & &1.object.guid) == [carried.object.guid]

      assert MapSet.new(Inventory.bank_items(player, lookup), & &1.object.guid) ==
               MapSet.new([banked.object.guid, bank_bag.object.guid, contained.object.guid])

      assert MapSet.new(Inventory.all_owned_items(player, lookup), & &1.object.guid) ==
               MapSet.new([carried.object.guid, banked.object.guid, bank_bag.object.guid, contained.object.guid])
    end

    test "ignores missing entries, loops, and duplicate GUIDs" do
      item = build_item(20, %ItemTemplate{entry: 2000, inventory_type: 18, container_slots: 6, class: 1})
      item = put_in(item.container.slot_1, item.object.guid)
      player = %Player{inv1: item.object.guid, bank1: item.object.guid, bank2: 999}

      assert Inventory.all_owned_items(player, get_item_fn([item])) == [item]
    end

    test "counts carried items separately from bank items" do
      template = %ItemTemplate{entry: 2000, stackable: 20}
      carried = build_item(20, template, stack_count: 3)
      banked = build_item(21, template, stack_count: 4)
      player = %Player{inv1: carried.object.guid, bank1: banked.object.guid}
      lookup = get_item_fn([carried, banked])

      assert Inventory.count_entry(player, 2000, lookup) == 3
      assert Inventory.count_entry_with_bank(player, 2000, lookup) == 7
    end
  end

  describe "bank transitions" do
    test "swaps across carried and bank positions in every direction", %{unit: unit} do
      carried1 = build_item(20, %ItemTemplate{entry: 2000})
      carried2 = build_item(21, %ItemTemplate{entry: 2001})
      banked1 = build_item(22, %ItemTemplate{entry: 2002})
      banked2 = build_item(23, %ItemTemplate{entry: 2003})

      player = %Player{
        inv1: carried1.object.guid,
        inv2: carried2.object.guid,
        bank1: banked1.object.guid,
        bank2: banked2.object.guid
      }

      lookup = get_item_fn([carried1, carried2, banked1, banked2])

      assert {:ok, first} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bag_0, @bank_start},
                 lookup
               )

      assert first.player.inv1 == banked1.object.guid
      assert first.player.bank1 == carried1.object.guid

      assert {:ok, second} =
               Inventory.swap(
                 first.player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @bank_start},
                 {@bag_0, @bank_start + 1},
                 lookup
               )

      assert second.player.bank1 == banked2.object.guid
      assert second.player.bank2 == carried1.object.guid

      assert {:ok, third} =
               Inventory.swap(
                 second.player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @backpack_start + 1},
                 {@bag_0, @backpack_start},
                 lookup
               )

      assert third.player.inv1 == carried2.object.guid
      assert third.player.inv2 == banked1.object.guid
    end

    test "auto-banks by merging before using an empty base slot" do
      template = %ItemTemplate{entry: 2000, stackable: 10}
      carried = build_item(20, template, stack_count: 5)
      banked = build_item(21, template, stack_count: 8)
      player = %Player{inv1: carried.object.guid, bank1: banked.object.guid}

      assert {:ok, result} =
               Inventory.auto_store(
                 player,
                 @owner,
                 {@bag_0, @backpack_start},
                 :bank,
                 get_item_fn([carried, banked])
               )

      assert result.player.inv1 == 0
      assert result.player.bank2 == carried.object.guid
      assert updated(result.items, banked).item.stack_count == 10
      assert updated(result.items, carried).item.stack_count == 3
    end

    test "auto-withdraws by merging before using the current carried order" do
      template = %ItemTemplate{entry: 2000, stackable: 10}
      banked = build_item(20, template, stack_count: 5)
      carried = build_item(21, template, stack_count: 8)
      player = %Player{bank1: banked.object.guid, inv1: carried.object.guid}

      assert {:ok, result} =
               Inventory.auto_store(
                 player,
                 @owner,
                 {@bag_0, @bank_start},
                 :carried,
                 get_item_fn([banked, carried])
               )

      assert result.player.bank1 == 0
      assert result.player.inv2 == banked.object.guid
      assert updated(result.items, carried).item.stack_count == 10
      assert updated(result.items, banked).item.stack_count == 3
    end

    test "returns full errors without mutating either storage scope" do
      source = build_item(20, %ItemTemplate{entry: 2000})
      filler = build_item(21, %ItemTemplate{entry: 2001})

      bank_full =
        Enum.reduce(1..24, %Player{inv1: source.object.guid}, fn index, player ->
          Map.put(player, :"bank#{index}", filler.object.guid)
        end)

      assert {:error, :bank_full, _, 0} =
               Inventory.auto_store(
                 bank_full,
                 @owner,
                 {@bag_0, @backpack_start},
                 :bank,
                 get_item_fn([source, filler])
               )

      assert bank_full.inv1 == source.object.guid

      carried_full =
        Enum.reduce(1..16, %Player{bank1: source.object.guid}, fn index, player ->
          Map.put(player, :"inv#{index}", filler.object.guid)
        end)

      assert {:error, :inventory_full, _, 0} =
               Inventory.auto_store(
                 carried_full,
                 @owner,
                 {@bag_0, @bank_start},
                 :carried,
                 get_item_fn([source, filler])
               )

      assert carried_full.bank1 == source.object.guid
    end

    test "uses eligible specialized bank bags before base slots" do
      herb = build_item(20, %ItemTemplate{entry: 2000, bag_family: 0x20})

      herb_bag =
        build_item(
          21,
          %ItemTemplate{entry: 2001, inventory_type: 18, container_slots: 6, class: 1, bag_family: 0x20}
        )

      player = %Player{inv1: herb.object.guid, bank_bag1: herb_bag.object.guid, bank_bag_slots: 1}

      assert {:ok, result} =
               Inventory.auto_store(
                 player,
                 @owner,
                 {@bag_0, @backpack_start},
                 :bank,
                 get_item_fn([herb, herb_bag])
               )

      assert updated(result.items, herb_bag).container.slot_1 == herb.object.guid
      assert result.player.bank1 in [nil, 0]
    end

    test "rejects incompatible manual bag placement", %{unit: unit} do
      ordinary = build_item(20, %ItemTemplate{entry: 2000})

      herb_bag =
        build_item(
          21,
          %ItemTemplate{entry: 2001, inventory_type: 18, container_slots: 6, class: 1, bag_family: 0x20}
        )

      player = %Player{inv1: ordinary.object.guid, bank_bag1: herb_bag.object.guid, bank_bag_slots: 1}

      assert {:error, :item_doesnt_go_to_slot, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @backpack_start},
                 {@bank_bag_start, 0},
                 get_item_fn([ordinary, herb_bag])
               )
    end

    test "rejects splitting a stack into an incompatible bank bag" do
      stack = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 5)
      split = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 2)

      herb_bag =
        build_item(
          22,
          %ItemTemplate{entry: 2001, inventory_type: 18, container_slots: 6, class: 1, bag_family: 0x20}
        )

      player = %Player{bank1: stack.object.guid, bank_bag1: herb_bag.object.guid, bank_bag_slots: 1}

      assert {:error, :couldnt_split_items, _, _} =
               Inventory.split(
                 player,
                 @owner,
                 {@bag_0, @bank_start},
                 {@bank_bag_start, 0},
                 split,
                 get_item_fn([stack, herb_bag])
               )
    end

    test "requires bank bags to be empty when placing and removing them", %{unit: unit, bag: bag, chest: chest} do
      bag = put_in(bag.container.slot_1, chest.object.guid)
      player = %Player{bag1: bag.object.guid, bank_bag_slots: 1}

      assert {:error, :can_only_do_with_empty_bags, _, 0} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @first_bag_slot},
                 {@bag_0, @bank_bag_start},
                 get_item_fn([bag, chest])
               )

      empty_bag = %{bag | container: %{bag.container | slot_1: 0}}
      player = %Player{bag1: empty_bag.object.guid, bank_bag_slots: 1}

      assert {:ok, placed} =
               Inventory.swap(
                 player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @first_bag_slot},
                 {@bag_0, @bank_bag_start},
                 get_item_fn([empty_bag])
               )

      assert placed.player.bank_bag1 == empty_bag.object.guid

      assert {:ok, removed} =
               Inventory.swap(
                 placed.player,
                 unit,
                 @prof,
                 @owner,
                 {@bag_0, @bank_bag_start},
                 {@bag_0, @first_bag_slot},
                 get_item_after(placed, get_item_fn([empty_bag]))
               )

      assert removed.player.bag1 == empty_bag.object.guid
    end

    test "splits and destroys stacks in bank storage" do
      stack = build_item(20, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 8)
      split = build_item(21, %ItemTemplate{entry: 2000, stackable: 10}, stack_count: 3)
      player = store_bank(%Player{}, @bank_start, stack)

      assert {:ok, split_result, placed} =
               Inventory.split(
                 player,
                 @owner,
                 {@bag_0, @bank_start},
                 {@bag_0, @bank_start + 1},
                 split,
                 get_item_fn([stack])
               )

      assert split_result.player.bank2 == split.object.guid
      assert updated(split_result.items, stack).item.stack_count == 5
      assert placed.object.guid == split.object.guid

      lookup = get_item_after(split_result, get_item_fn([stack, split]))

      assert {:ok, destroyed, item} =
               Inventory.destroy(split_result.player, {@bag_0, @bank_start + 1}, lookup)

      assert destroyed.player.bank2 == 0
      assert item.object.guid == split.object.guid
    end

    test "ordinary storage and removals remain carried-only" do
      banked = build_item(20, %ItemTemplate{entry: 2000})
      incoming = build_item(21, %ItemTemplate{entry: 2001})
      player = %Player{bank1: banked.object.guid}
      lookup = get_item_fn([banked, incoming])

      assert {:error, :item_not_found, 0, 0} = Inventory.remove_count(player, 2000, 1, lookup)

      assert {:ok, stored, {:placed, {@bag_0, @backpack_start}, _item}} =
               Inventory.store(player, @owner, incoming, lookup)

      assert stored.player.inv1 == incoming.object.guid
      assert stored.player.bank1 == banked.object.guid

      batch = player |> Batch.new() |> Batch.remove(2000, 1)
      assert {:error, :item_not_found} = Inventory.plan(batch, lookup)
    end
  end
end
