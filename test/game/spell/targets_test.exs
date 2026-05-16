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

    test "unit target unpacks the target guid" do
      payload = <<0x02::little-size(16)>> <> BinaryUtils.pack_guid(0xAABBCC)

      targets = Targets.parse(payload, 123)

      assert targets.unit_guid == 0xAABBCC
      assert targets.raw == payload
    end

    test "destination location parses ground-target coordinates" do
      payload =
        <<0x40::little-size(16)>> <>
          <<1.0::little-float-size(32), 2.0::little-float-size(32), 3.0::little-float-size(32)>>

      targets = Targets.parse(payload, 123)

      assert targets.destination_location == {1.0, 2.0, 3.0}
      assert targets.unit_guid == nil
    end
  end
end
