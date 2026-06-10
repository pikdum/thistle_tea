defmodule ThistleTea.Game.Entity.Logic.InventoryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory

  @mainhand_slot 15
  @offhand_slot 16
  @backpack_start 23

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
     priest_only: build_item(7, %ItemTemplate{entry: 700, inventory_type: 5, allowable_class: 16})}
  end

  defp build_item(low_guid, template) do
    Item.build(template, 0x4000_0000_0000_0000 + low_guid, owner: 1)
  end

  defp get_item_fn(items) do
    by_guid = Map.new(items, fn item -> {item.object.guid, item} end)
    fn guid -> Map.get(by_guid, guid) end
  end

  defp store(player, slot, item) do
    Map.put(player, :"inv#{slot - @backpack_start + 1}", item.object.guid)
  end

  describe "equip/3" do
    test "sets slot guid and visible entry", %{chest: chest} do
      player = Inventory.equip(%Player{}, :chest, chest)

      assert player.chest == chest.object.guid
      assert player.visible_item_5_0 == 100
    end
  end

  describe "equipped_guids/1" do
    test "lists only populated equipment slots", %{chest: chest} do
      player =
        %Player{}
        |> Inventory.equip(:chest, chest)
        |> Map.put(:head, 0)

      assert Inventory.equipped_guids(player) == [chest.object.guid]
    end
  end

  describe "auto_equip/4" do
    test "equips into the matching empty slot", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:ok, player} = Inventory.auto_equip(player, unit, @backpack_start, get_item_fn([chest]))
      assert player.chest == chest.object.guid
      assert player.visible_item_5_0 == 100
      assert player.inv1 == 0
    end

    test "swaps with the currently equipped item", %{unit: unit, chest: chest, high_level: _} do
      other_chest = build_item(8, %ItemTemplate{entry: 800, inventory_type: 5})

      player =
        %Player{}
        |> Inventory.equip(:chest, other_chest)
        |> store(@backpack_start, chest)

      assert {:ok, player} = Inventory.auto_equip(player, unit, @backpack_start, get_item_fn([chest, other_chest]))
      assert player.chest == chest.object.guid
      assert player.visible_item_5_0 == 100
      assert player.inv1 == other_chest.object.guid
    end

    test "prefers a free slot for rings", %{unit: unit, ring: ring} do
      other_ring = build_item(9, %ItemTemplate{entry: 900, inventory_type: 11})

      player =
        %Player{}
        |> Inventory.equip(:finger1, other_ring)
        |> store(@backpack_start, ring)

      assert {:ok, player} = Inventory.auto_equip(player, unit, @backpack_start, get_item_fn([ring, other_ring]))
      assert player.finger1 == other_ring.object.guid
      assert player.finger2 == ring.object.guid
    end

    test "rejects empty source slot", %{unit: unit} do
      assert {:error, :item_not_found, 0, 0} = Inventory.auto_equip(%Player{}, unit, @backpack_start, fn _ -> nil end)
    end

    test "rejects items above the player level", %{unit: unit, high_level: high_level} do
      player = store(%Player{}, @backpack_start, high_level)

      assert {:error, :cant_equip_level_i, guid, 0} =
               Inventory.auto_equip(player, unit, @backpack_start, get_item_fn([high_level]))

      assert guid == high_level.object.guid
    end

    test "rejects items for other classes", %{unit: unit, priest_only: priest_only} do
      player = store(%Player{}, @backpack_start, priest_only)

      assert {:error, :you_can_never_use_that_item, _, 0} =
               Inventory.auto_equip(player, unit, @backpack_start, get_item_fn([priest_only]))
    end
  end

  describe "swap/5" do
    test "swaps two backpack slots", %{unit: unit, chest: chest, sword: sword} do
      player =
        %Player{}
        |> store(@backpack_start, chest)
        |> store(@backpack_start + 1, sword)

      assert {:ok, player} =
               Inventory.swap(player, unit, @backpack_start, @backpack_start + 1, get_item_fn([chest, sword]))

      assert player.inv1 == sword.object.guid
      assert player.inv2 == chest.object.guid
    end

    test "swaps rings between finger slots", %{unit: unit, ring: ring} do
      player = Inventory.equip(%Player{}, :finger1, ring)

      assert {:ok, player} = Inventory.swap(player, unit, 10, 11, get_item_fn([ring]))
      assert player.finger1 == 0
      assert player.finger2 == ring.object.guid
      assert player.visible_item_11_0 == 0
      assert player.visible_item_12_0 == 500
    end

    test "rejects equipping into the wrong slot", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:error, :item_doesnt_go_to_slot, _, _} =
               Inventory.swap(player, unit, @backpack_start, @mainhand_slot, get_item_fn([chest]))
    end

    test "rejects offhand while a two-hander is equipped", %{unit: unit, greatsword: greatsword, shield: shield} do
      player =
        %Player{}
        |> Inventory.equip(:mainhand, greatsword)
        |> store(@backpack_start, shield)

      assert {:error, :cant_equip_with_twohanded, _, _} =
               Inventory.swap(player, unit, @backpack_start, @offhand_slot, get_item_fn([greatsword, shield]))
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

      assert {:ok, player} =
               Inventory.swap(player, unit, @backpack_start, @mainhand_slot, get_item_fn([greatsword, shield, sword]))

      assert player.mainhand == greatsword.object.guid
      assert player.offhand == 0
      assert player.visible_item_17_0 == 0
      assert player.inv1 == sword.object.guid
      assert player.inv2 == shield.object.guid
    end

    test "rejects a two-hander when the offhand cannot be stored", %{
      unit: unit,
      greatsword: greatsword,
      shield: shield,
      sword: sword
    } do
      filler = build_item(10, %ItemTemplate{entry: 1000, inventory_type: 0})

      player =
        %Player{}
        |> Inventory.equip(:mainhand, sword)
        |> Inventory.equip(:offhand, shield)
        |> store(@backpack_start, greatsword)

      player = Enum.reduce(1..15, player, fn i, p -> store(p, @backpack_start + i, filler) end)

      assert {:error, :cant_equip_with_twohanded, _, _} =
               Inventory.swap(
                 player,
                 unit,
                 @backpack_start,
                 @mainhand_slot,
                 get_item_fn([greatsword, shield, sword, filler])
               )
    end

    test "same slot is a no-op", %{unit: unit, chest: chest} do
      player = store(%Player{}, @backpack_start, chest)

      assert {:ok, ^player} = Inventory.swap(player, unit, @backpack_start, @backpack_start, get_item_fn([chest]))
    end
  end

  describe "destroy/3" do
    test "clears the slot and returns the item", %{chest: chest} do
      player = Inventory.equip(%Player{}, :chest, chest)

      assert {:ok, player, item} = Inventory.destroy(player, 4, get_item_fn([chest]))
      assert item == chest
      assert player.chest == 0
      assert player.visible_item_5_0 == 0
    end

    test "rejects empty slots" do
      assert {:error, :item_not_found, 0, 0} = Inventory.destroy(%Player{}, 4, fn _ -> nil end)
    end

    test "rejects indestructible items" do
      totem = build_item(11, %ItemTemplate{entry: 1100, inventory_type: 0, flags: 0x20})
      player = store(%Player{}, @backpack_start, totem)

      assert {:error, :cant_drop_soulbound, _, 0} = Inventory.destroy(player, @backpack_start, get_item_fn([totem]))
    end
  end

  describe "can_use/2" do
    test "allows matching class and level", %{unit: unit} do
      assert :ok = Inventory.can_use(unit, %ItemTemplate{})
    end

    test "honors allowable race masks", %{unit: unit} do
      assert {:error, :you_can_never_use_that_item} = Inventory.can_use(unit, %ItemTemplate{allowable_race: 2})
      assert :ok = Inventory.can_use(unit, %ItemTemplate{allowable_race: 1})
    end
  end
end
