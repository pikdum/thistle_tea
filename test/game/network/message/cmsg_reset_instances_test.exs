defmodule ThistleTea.Game.Network.Message.CmsgResetInstancesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Network.Message.CmsgResetInstances
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgInstanceReset
  alias ThistleTea.Game.Network.Message.SmsgInstanceResetFailed
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  describe "from_binary/1" do
    test "decodes the empty request" do
      assert CmsgResetInstances.from_binary(<<>>) == %CmsgResetInstances{}
      assert Dispatch.implemented?(Opcodes.get(:CMSG_RESET_INSTANCES))
    end
  end

  describe "handle/2" do
    test "resets an empty owned instance" do
      guid = System.unique_integer([:positive])
      state = %{ready: true, guid: guid}
      assert {:ok, world} = InstanceSystem.enter(389, guid)
      InstanceSystem.leave(guid, world)

      assert CmsgResetInstances.handle(%CmsgResetInstances{}, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInstanceReset{map: 389}}}
    end

    test "reports an occupied instance" do
      guid = System.unique_integer([:positive])
      state = %{ready: true, guid: guid}
      assert {:ok, world} = InstanceSystem.enter(389, guid)

      assert CmsgResetInstances.handle(%CmsgResetInstances{}, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInstanceResetFailed{reason: 0, map: 389}}}

      InstanceSystem.leave(guid, world)
      InstanceSystem.reset(guid)
    end
  end

  describe "server codecs" do
    test "encodes reset results" do
      assert SmsgInstanceReset.to_binary(%SmsgInstanceReset{map: 389}) == <<389::little-size(32)>>

      assert SmsgInstanceResetFailed.to_binary(%SmsgInstanceResetFailed{reason: 2, map: 389}) ==
               <<2::little-size(32), 389::little-size(32)>>
    end
  end
end
