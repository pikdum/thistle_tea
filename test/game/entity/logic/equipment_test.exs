defmodule ThistleTea.Game.Entity.Logic.EquipmentTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Equipment

  setup [:build_item]

  defp build_item(_context) do
    template = %ItemTemplate{entry: 1234, inventory_type: 5, max_durability: 50}
    item = Item.build(template, 0x4000_0000_0000_0001, owner: 7)
    {:ok, item: item}
  end

  describe "equip/3" do
    test "sets slot guid and visible entry", %{item: item} do
      player = Equipment.equip(%Player{}, :chest, item)

      assert player.chest == item.object.guid
      assert player.visible_item_5_0 == 1234
    end
  end

  describe "clear/2" do
    test "removes slot guid", %{item: item} do
      player =
        %Player{}
        |> Equipment.equip(:chest, item)
        |> Equipment.clear(:chest)

      assert player.chest == nil
      assert player.visible_item_5_0 == 1234
    end
  end

  describe "equipped_guids/1" do
    test "lists only populated slots", %{item: item} do
      player =
        %Player{}
        |> Equipment.equip(:chest, item)
        |> Map.put(:head, 0)

      assert Equipment.equipped_guids(player) == [item.object.guid]
    end
  end

  describe "visible_entry/2" do
    test "reads the visible item entry for a slot", %{item: item} do
      player = Equipment.equip(%Player{}, :mainhand, item)

      assert Equipment.visible_entry(player, :mainhand) == 1234
      assert Equipment.visible_entry(player, :offhand) == nil
    end
  end

  describe "slots/0" do
    test "covers all 19 equipment slots" do
      assert length(Equipment.slots()) == 19
      assert Equipment.visible_entry_field(:tabard) == :visible_item_19_0
    end
  end
end
