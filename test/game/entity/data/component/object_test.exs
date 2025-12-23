defmodule ThistleTea.Game.Entity.Data.Component.ObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Object

  describe "struct" do
    test "has correct fields" do
      assert %Object{} == %Object{guid: nil, type: nil, entry: nil, scale_x: nil}
    end

    test "creates object with values" do
      object = %Object{
        guid: 0x1234567890,
        type: 5,
        entry: 100,
        scale_x: 1.0
      }

      assert object.guid == 0x1234567890
      assert object.type == 5
      assert object.entry == 100
      assert object.scale_x == 1.0
    end
  end
end
