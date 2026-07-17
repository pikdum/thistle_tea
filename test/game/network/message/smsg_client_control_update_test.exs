defmodule ThistleTea.Game.Network.Message.SmsgClientControlUpdateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.SmsgClientControlUpdate

  describe "to_binary/1" do
    test "serializes the packed mover guid and movement permission" do
      guid = 0xAABB

      assert SmsgClientControlUpdate.to_binary(%SmsgClientControlUpdate{guid: guid, allow_movement?: true}) ==
               BinaryUtils.pack_guid(guid) <> <<1>>

      assert SmsgClientControlUpdate.to_binary(%SmsgClientControlUpdate{guid: guid}) ==
               BinaryUtils.pack_guid(guid) <> <<0>>
    end
  end
end
