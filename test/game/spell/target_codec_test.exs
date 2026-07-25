defmodule ThistleTea.Game.Spell.TargetCodecTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec

  describe "parse/2" do
    test "self target uses caster guid" do
      target = TargetCodec.parse(<<0::little-size(16)>>, 123)

      assert target == Target.self(123)
    end

    test "short payload falls back to self target" do
      assert TargetCodec.parse(<<>>, 123) == Target.self(123)
    end

    test "unit target unpacks the target guid" do
      payload = <<0x02::little-size(16)>> <> BinaryUtils.pack_guid(0xAABBCC)

      assert TargetCodec.parse(payload, 123) == Target.unit(0xAABBCC)
    end

    test "item target unpacks the target guid" do
      payload = <<0x10::little-size(16)>> <> BinaryUtils.pack_guid(0x4000_00AA)

      assert TargetCodec.parse(payload, 123) == Target.item(0x4000_00AA)
    end

    test "truncated unit target leaves the semantic selection empty" do
      payload = <<0x02::little-size(16), 0xFF::8, 0xAA::8>>

      assert TargetCodec.parse(payload, 123) == Target.none()
    end

    test "object target retains its access mode" do
      open_payload = <<0x0800::little-size(16)>> <> BinaryUtils.pack_guid(0xF110_0001)
      locked_payload = <<0x4000::little-size(16)>> <> BinaryUtils.pack_guid(0xF110_0002)

      assert TargetCodec.parse(open_payload, 123) == Target.object(0xF110_0001)
      assert TargetCodec.parse(locked_payload, 123) == Target.object(0xF110_0002, :locked)
    end

    test "destination location parses ground-target coordinates" do
      payload =
        <<0x40::little-size(16)>> <>
          <<1.0::little-float-size(32), 2.0::little-float-size(32), 3.0::little-float-size(32)>>

      assert TargetCodec.parse(payload, 123) == Target.at({1.0, 2.0, 3.0})
    end

    test "unit and destination location parse in field order" do
      payload =
        <<0x42::little-size(16)>> <>
          BinaryUtils.pack_guid(0xAABBCC) <>
          <<1.0::little-float-size(32), 2.0::little-float-size(32), 3.0::little-float-size(32)>>

      target = TargetCodec.parse(payload, 123)

      assert target.selection == {:unit, 0xAABBCC}
      assert target.destination_location == {1.0, 2.0, 3.0}
    end

    test "source location parses ground-target coordinates" do
      payload =
        <<0x20::little-size(16)>> <>
          <<4.0::little-float-size(32), 5.0::little-float-size(32), 6.0::little-float-size(32)>>

      target = TargetCodec.parse(payload, 123)

      assert target.source_location == {4.0, 5.0, 6.0}
      assert Target.ground_location(target) == {4.0, 5.0, 6.0}
    end
  end

  describe "encode/1" do
    test "round trips combined semantic targets" do
      target = %Target{selection: {:unit, 0xAABBCC}, destination_location: {1.0, 2.0, 3.0}}

      assert target |> TargetCodec.encode() |> TargetCodec.parse(123) == target
    end
  end

  describe "Target.ground_location/1" do
    test "prefers destination over source" do
      target = %Target{
        selection: :none,
        source_location: {1.0, 1.0, 1.0},
        destination_location: {2.0, 2.0, 2.0}
      }

      assert Target.ground_location(target) == {2.0, 2.0, 2.0}
    end
  end
end
