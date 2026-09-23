defmodule ThistleTea.Game.Network.Message.InstanceAdmissionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgRaidGroupOnly
  alias ThistleTea.Game.Network.Message.SmsgTransferAborted
  alias ThistleTea.Game.Network.Opcodes

  describe "SMSG_TRANSFER_ABORTED" do
    test "encodes the one-byte vanilla reason without a later-expansion map id" do
      assert SmsgTransferAborted.to_binary(%SmsgTransferAborted{reason: :instance_full}) == <<1>>
      assert SmsgTransferAborted.to_binary(%SmsgTransferAborted{reason: :instance_unavailable}) == <<2>>
      assert SmsgTransferAborted.to_binary(%SmsgTransferAborted{reason: :too_many_instances}) == <<3>>
      assert SmsgTransferAborted.opcode() == Opcodes.get(:SMSG_TRANSFER_ABORTED)
    end
  end

  describe "SMSG_RAID_GROUP_ONLY" do
    test "encodes the home timer and reason as uint32 values" do
      assert SmsgRaidGroupOnly.to_binary(%SmsgRaidGroupOnly{}) == <<0::little-size(32), 1::little-size(32)>>
      assert SmsgRaidGroupOnly.opcode() == Opcodes.get(:SMSG_RAID_GROUP_ONLY)
    end
  end
end
