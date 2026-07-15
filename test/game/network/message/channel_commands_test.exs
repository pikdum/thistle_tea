defmodule ThistleTea.Game.Network.Message.ChannelCommandsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message

  describe "from_binary/1" do
    test "parses channel-only commands" do
      modules = [
        Message.CmsgChannelList,
        Message.CmsgChannelOwner,
        Message.CmsgChannelAnnouncements,
        Message.CmsgChannelModerate
      ]

      Enum.each(modules, fn module ->
        assert %{channel_name: "Custom"} = module.from_binary(<<"Custom", 0>>)
      end)
    end

    test "parses channel and player commands" do
      modules = [
        Message.CmsgChannelSetOwner,
        Message.CmsgChannelModerator,
        Message.CmsgChannelUnmoderator,
        Message.CmsgChannelMute,
        Message.CmsgChannelUnmute,
        Message.CmsgChannelInvite,
        Message.CmsgChannelKick,
        Message.CmsgChannelBan,
        Message.CmsgChannelUnban
      ]

      Enum.each(modules, fn module ->
        assert %{channel_name: "Custom", player_name: "Player"} =
                 module.from_binary(<<"Custom", 0, "Player", 0>>)
      end)
    end

    test "parses channel passwords" do
      assert %Message.CmsgChannelPassword{channel_name: "Custom", password: "secret"} =
               Message.CmsgChannelPassword.from_binary(<<"Custom", 0, "secret", 0>>)
    end
  end
end
