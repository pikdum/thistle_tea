defmodule ThistleTea.Game.Network.Message.MsgChannelStartTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.MsgChannelStart
  alias ThistleTea.Game.Network.Message.MsgChannelUpdate

  describe "to_binary/1" do
    test "serializes channel start" do
      assert MsgChannelStart.to_binary(%MsgChannelStart{spell_id: 10, duration_ms: 8_000}) ==
               <<10::little-size(32), 8_000::little-size(32)>>
    end

    test "serializes channel update" do
      assert MsgChannelUpdate.to_binary(%MsgChannelUpdate{time_ms: 0}) == <<0::little-size(32)>>
    end
  end
end
