defmodule ThistleTea.Game.Network.Message.CmsgZoneupdateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgZoneupdate
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes

  describe "from_binary/1" do
    test "parses the client-reported area" do
      assert %CmsgZoneupdate{area: 14} = CmsgZoneupdate.from_binary(<<14::little-size(32)>>)
    end

    test "tolerates an empty payload" do
      assert %CmsgZoneupdate{area: nil} = CmsgZoneupdate.from_binary(<<>>)
    end
  end

  describe "handle/2" do
    test "is a no-op before the player is in the world" do
      state = %{ready: false, character: nil}

      assert CmsgZoneupdate.handle(%CmsgZoneupdate{area: 14}, state) == state
    end
  end

  describe "Dispatch.implemented?/1" do
    test "recognizes the zone update opcode" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_ZONEUPDATE))
    end
  end
end
