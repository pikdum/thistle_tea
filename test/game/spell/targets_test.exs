defmodule ThistleTea.Game.Spell.TargetsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Spell.Targets

  describe "parse/2" do
    test "self target uses caster guid" do
      targets = Targets.parse(<<0::little-size(16)>>, 123)

      assert targets.flags == 0
      assert targets.raw == <<0::little-size(16)>>
      assert targets.unit_guid == 123
    end

    test "short payload falls back to self target" do
      targets = Targets.parse(<<>>, 123)

      assert targets.flags == 0
      assert targets.raw == <<0::little-size(16)>>
      assert targets.unit_guid == 123
    end

    test "unit target unpacks the target guid" do
      payload = <<0x02::little-size(16)>> <> BinaryUtils.pack_guid(0xAABBCC)

      targets = Targets.parse(payload, 123)

      assert targets.unit_guid == 0xAABBCC
      assert targets.raw == payload
    end

    test "item target unpacks the target guid" do
      payload = <<0x10::little-size(16)>> <> BinaryUtils.pack_guid(0x4000_00AA)

      targets = Targets.parse(payload, 123)

      assert targets.item_guid == 0x4000_00AA
      assert targets.unit_guid == nil
    end

    test "truncated unit target leaves target unset" do
      payload = <<0x02::little-size(16), 0xFF::8, 0xAA::8>>

      targets = Targets.parse(payload, 123)

      assert targets.flags == 0x02
      assert targets.raw == payload
      assert targets.unit_guid == nil
    end

    test "object target unpacks the object guid" do
      payload = <<0x0800::little-size(16)>> <> BinaryUtils.pack_guid(0xF110_0001)

      targets = Targets.parse(payload, 123)

      assert targets.object_guid == 0xF110_0001
      assert targets.unit_guid == nil
    end

    test "locked object target unpacks the object guid" do
      payload = <<0x4000::little-size(16)>> <> BinaryUtils.pack_guid(0xF110_0002)

      targets = Targets.parse(payload, 123)

      assert targets.object_guid == 0xF110_0002
    end

    test "destination location parses ground-target coordinates" do
      payload =
        <<0x40::little-size(16)>> <>
          <<1.0::little-float-size(32), 2.0::little-float-size(32), 3.0::little-float-size(32)>>

      targets = Targets.parse(payload, 123)

      assert targets.destination_location == {1.0, 2.0, 3.0}
      assert targets.unit_guid == nil
    end

    test "unit and destination location parse in field order" do
      payload =
        <<0x42::little-size(16)>> <>
          BinaryUtils.pack_guid(0xAABBCC) <>
          <<1.0::little-float-size(32), 2.0::little-float-size(32), 3.0::little-float-size(32)>>

      targets = Targets.parse(payload, 123)

      assert targets.unit_guid == 0xAABBCC
      assert targets.destination_location == {1.0, 2.0, 3.0}
    end

    test "source location parses ground-target coordinates" do
      payload =
        <<0x20::little-size(16)>> <>
          <<4.0::little-float-size(32), 5.0::little-float-size(32), 6.0::little-float-size(32)>>

      targets = Targets.parse(payload, 123)

      assert targets.source_location == {4.0, 5.0, 6.0}
      assert Targets.ground_location(targets) == {4.0, 5.0, 6.0}
    end
  end

  describe "ground_location/1" do
    test "prefers destination over source" do
      targets = %Targets{source_location: {1.0, 1.0, 1.0}, destination_location: {2.0, 2.0, 2.0}}

      assert Targets.ground_location(targets) == {2.0, 2.0, 2.0}
    end
  end
end
