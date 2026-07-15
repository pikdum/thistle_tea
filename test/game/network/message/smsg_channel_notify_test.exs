defmodule ThistleTea.Game.Network.Message.SmsgChannelNotifyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgChannelNotify

  describe "to_binary/1" do
    test "serializes you joined with channel flags and index" do
      message = %SmsgChannelNotify{
        notify_type: SmsgChannelNotify.notice().you_joined,
        channel_name: "General - Elwynn Forest",
        channel_flags: 0x18,
        channel_index: 0
      }

      assert SmsgChannelNotify.to_binary(message) ==
               <<0x02, "General - Elwynn Forest", 0, 0x18::little-size(32), 0::little-size(32)>>
    end

    test "defaults missing you joined fields to zero" do
      message = %SmsgChannelNotify{
        notify_type: SmsgChannelNotify.notice().you_joined,
        channel_name: "Custom"
      }

      assert SmsgChannelNotify.to_binary(message) ==
               <<0x02, "Custom", 0, 0::little-size(32), 0::little-size(32)>>
    end

    test "serializes notices without a variant body" do
      message = %SmsgChannelNotify{
        notify_type: SmsgChannelNotify.notice().you_left,
        channel_name: "Custom"
      }

      assert SmsgChannelNotify.to_binary(message) == <<0x03, "Custom", 0>>
    end
  end
end
