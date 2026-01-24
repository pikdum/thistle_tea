defmodule ThistleTea.Game.GuidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guid

  describe "from_low_guid/2" do
    test "builds player guid" do
      guid = Guid.from_low_guid(:player, 42)

      assert guid == 42
      assert Guid.high_guid(guid) == Guid.high_guid(:player)
      assert Guid.low_guid(guid) == 42
    end

    test "builds item guid" do
      guid = Guid.from_low_guid(:item, 0xBEEF)

      assert Guid.high_guid(guid) == Guid.high_guid(:item)
      assert Guid.low_guid(guid) == 0xBEEF
    end
  end

  describe "from_low_guid/3" do
    test "builds mob guid with entry" do
      guid = Guid.from_low_guid(:mob, 0x1A2B, 0x2C3D)

      assert Guid.high_guid(guid) == Guid.high_guid(:mob)
      assert Guid.entry(guid) == 0x1A2B
      assert Guid.low_guid(guid) == 0x2C3D
    end
  end

  describe "split/1" do
    test "returns high and low guid" do
      guid = Guid.from_low_guid(:game_object, 12, 34)

      assert Guid.split(guid) == {Guid.high_guid(:game_object), 34}
    end
  end

  describe "entity_type/1" do
    test "returns entity type" do
      player_guid = Guid.from_low_guid(:player, 1)
      mob_guid = Guid.from_low_guid(:mob, 2, 3)
      game_object_guid = Guid.from_low_guid(:game_object, 4, 5)

      assert Guid.entity_type(player_guid) == :player
      assert Guid.entity_type(mob_guid) == :mob
      assert Guid.entity_type(game_object_guid) == :game_object
    end

    test "returns nil for empty guid" do
      assert Guid.entity_type(0) == nil
    end
  end
end
