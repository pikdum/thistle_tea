defmodule ThistleTea.Game.Entity.Logic.ScriptEquipmentTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.ScriptEquipment

  describe "apply/2" do
    test "changes, preserves, and clears individual virtual slots" do
      current = %Unit{
        virtual_item_slot_display: 10 + Bitwise.bsl(20, 32) + Bitwise.bsl(30, 64),
        virtual_item_info:
          <<1, 2, 3, 4, 5, 0, 0, 0>> <>
            <<6, 7, 8, 9, 10, 0, 0, 0>> <>
            <<11, 12, 13, 14, 15, 0, 0, 0>>
      }

      item = %ItemTemplate{
        display_id: 99,
        class: 2,
        subclass: 7,
        material: 1,
        inventory_type: 13,
        sheath: 3
      }

      updated = ScriptEquipment.apply(current, [item, :unchanged, nil])

      assert Bitwise.band(updated.virtual_item_slot_display, 0xFFFFFFFF) == 99
      assert Bitwise.band(Bitwise.bsr(updated.virtual_item_slot_display, 32), 0xFFFFFFFF) == 20
      assert Bitwise.bsr(updated.virtual_item_slot_display, 64) == 0

      assert updated.virtual_item_info ==
               <<2, 7, 1, 13, 3, 0, 0, 0>> <>
                 <<6, 7, 8, 9, 10, 0, 0, 0>> <>
                 <<0::64>>
    end
  end

  describe "reset/2" do
    test "restores the spawn snapshot" do
      current = %Unit{virtual_item_slot_display: 99, virtual_item_info: <<1::64, 2::64, 3::64>>}
      default = %Unit{virtual_item_slot_display: 42, virtual_item_info: <<4::64, 5::64, 6::64>>}

      assert ScriptEquipment.reset(current, default).virtual_item_slot_display == 42
      assert ScriptEquipment.reset(current, default).virtual_item_info == default.virtual_item_info
    end
  end
end
