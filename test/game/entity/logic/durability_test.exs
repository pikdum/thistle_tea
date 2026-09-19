defmodule ThistleTea.Game.Entity.Logic.DurabilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Durability
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Skills

  setup [:inventory]

  describe "loss/5" do
    test "death wear uses maximum durability and leaves carried gear intact", %{player: player, get: get} do
      {:ok, changes} = Durability.loss(player, :percent, 10, :equipped, get)
      assert ChangeSet.get_item(changes, 1, get).item.durability == 42
      assert ChangeSet.get_item(changes, 2, get).item.durability == 47
      assert ChangeSet.get_item(changes, 3, get).item.durability == 47
      assert length(ChangeSet.changed_items(changes)) == 1
    end

    test "spirit healer wear includes bag contents but excludes the bank", %{player: player, get: get} do
      {:ok, changes} = Durability.loss(player, :percent, 25, :carried, get)
      assert ChangeSet.get_item(changes, 1, get).item.durability == 35
      assert ChangeSet.get_item(changes, 2, get).item.durability == 35
      assert ChangeSet.get_item(changes, 4, get).item.durability == 35
      assert ChangeSet.get_item(changes, 3, get).item.durability == 47
    end

    test "one hit wears only its selected slot", %{player: player, get: get} do
      {:ok, changes} = Durability.loss(player, :points, 1, :mainhand, get)
      assert [%Item{item: %{durability: 46}}] = ChangeSet.changed_items(changes)
      assert {:ok, %ChangeSet{changed: changes}} = Durability.loss(player, :points, 1, :head, get)
      assert changes == %{}
    end
  end

  describe "lose/3" do
    test "clamps wear, rounds percentages down, and preserves indestructible items", %{get: get} do
      assert Durability.lose(get.(1), :points, 1000).item.durability == 0
      assert Durability.lose(get.(1), :percent, 1).item.durability == 46
      assert Durability.lose(get.(1), :percent, 0) == get.(1)
      item = Item.build(%ItemTemplate{entry: 1, max_durability: 0}, 99)
      assert Durability.lose(item, :points, 1) == item
      refute Item.broken?(item)
      assert Item.broken?(Durability.lose(get.(1), :points, 1000))
    end
  end

  describe "repair/4" do
    test "repairs carried items with one payment and skips bank items", %{player: player, get: get} do
      {:ok, changes} = Durability.repair(player, 0, get, &price/1)
      assert changes.player.coinage == 910
      assert Enum.map(ChangeSet.changed_items(changes), & &1.object.guid) == [1, 2, 4]
      assert Enum.all?(ChangeSet.changed_items(changes), &(&1.item.durability == 50))
      assert ChangeSet.get_item(changes, 3, get).item.durability == 47
      assert get.(1).item.durability == 47
    end

    test "repairs one exact item without charging for other damage", %{player: player, get: get} do
      {:ok, changes} = Durability.repair(player, 2, get, &price/1)
      assert changes.player.coinage == 970
      assert [%Item{object: %{guid: 2}}] = ChangeSet.changed_items(changes)
    end

    test "rejects insufficient funds or missing prices without partial repair", %{player: player, get: get} do
      assert {:error, :not_enough_money} = Durability.repair(%{player | coinage: 89}, 0, get, &price/1)
      assert {:error, :missing_repair_cost} = Durability.repair(player, 0, get, fn _item -> nil end)
      assert get.(1).item.durability == 47
    end

    test "foreign and bank GUIDs cannot be repaired", %{player: player, get: get} do
      for guid <- [3, 999] do
        assert {:ok, %ChangeSet{player: ^player, changed: changes}} = Durability.repair(player, guid, get, &price/1)
        assert changes == %{}
      end
    end
  end

  describe "repair_cost/4" do
    test "uses DBC factors, truncates before discount, and charges at least one copper", %{get: get} do
      assert Durability.repair_cost(get.(1), 7, 1.25) == 26
      assert Durability.repair_cost(get.(1), 7, 1.25, 0.9) == 23
      assert Durability.repair_cost(get.(1), 0, 0) == 1
      repaired = %{get.(1) | item: %{get.(1).item | durability: 50}}
      assert Durability.repair_cost(repaired, 7, 1.25) == 0
    end
  end

  describe "equipment_entry/2" do
    test "broken equipment loses its gameplay entry while retaining its visible appearance", %{player: player, get: get} do
      broken = Durability.lose(get.(1), :points, 100)

      broken_get = fn
        1 -> broken
        guid -> get.(guid)
      end

      synced = Inventory.sync_broken_equipment(player, broken_get)
      assert synced.broken_equipment == [:mainhand]
      assert synced.visible_item_16_0 == player.visible_item_16_0
      assert Inventory.equipment_entry(synced, :mainhand) == 0
      assert Inventory.equipped_templates(synced, broken_get) == [Item.template(get.(5))]
      assert Skills.main_hand_weapon_skill(synced, fn _ -> Item.template(broken) end) == 162
      repaired = Inventory.sync_broken_equipment(synced, get)
      assert repaired.broken_equipment == []
      assert Inventory.equipment_entry(repaired, :mainhand) == 25
    end
  end

  describe "Inventory.plan/2" do
    test "rejects updates to removed or foreign items", %{player: player, get: get} do
      batch = player |> Batch.new() |> Batch.remove_item(1, 1) |> Batch.update(get.(1))
      assert {:error, :item_not_found} = Inventory.plan(batch, get)
      foreign = Item.build(%ItemTemplate{entry: 123}, 999)
      assert {:error, :item_not_found} = player |> Batch.new() |> Batch.update(foreign) |> Inventory.plan(get)
    end
  end

  defp price(item), do: Durability.repair_cost(item, 10, 1.0)

  defp inventory(_context) do
    template = %ItemTemplate{entry: 25, class: 2, subclass: 7, max_durability: 50}
    items = Map.new(1..4, fn guid -> {guid, Durability.lose(Item.build(template, guid, owner: 10), :points, 3)} end)
    bag = Item.build(%ItemTemplate{entry: 100, inventory_type: 18, container_slots: 4}, 5, owner: 10)
    bag = %{bag | container: %{bag.container | slot_1: 4}}
    items = Map.put(items, 5, bag)
    player = Inventory.equip(%Player{coinage: 1000, inv1: 2, bank1: 3, bag1: 5}, :mainhand, items[1])
    %{player: player, get: &Map.get(items, &1)}
  end
end
