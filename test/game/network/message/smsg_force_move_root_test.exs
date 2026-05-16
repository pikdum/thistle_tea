defmodule ThistleTea.Game.Network.Message.SmsgForceMoveRootTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.SmsgForceMoveRoot
  alias ThistleTea.Game.Network.Message.SmsgForceMoveUnroot

  describe "to_binary/1" do
    test "serializes force root movement events" do
      guid = 0xAABB

      assert SmsgForceMoveRoot.to_binary(%SmsgForceMoveRoot{guid: guid, move_event: 7}) ==
               BinaryUtils.pack_guid(guid) <> <<7::little-size(32)>>
    end

    test "serializes force unroot movement events" do
      guid = 0xAABB

      assert SmsgForceMoveUnroot.to_binary(%SmsgForceMoveUnroot{guid: guid, move_event: 8}) ==
               BinaryUtils.pack_guid(guid) <> <<8::little-size(32)>>
    end
  end
end
