defmodule ThistleTea.Game.Inbound.ChannelCommandsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound

  describe "from_binary/1" do
    test "parses channel-only commands" do
      modules = [
        Inbound.CmsgChannelList,
        Inbound.CmsgChannelOwner,
        Inbound.CmsgChannelAnnouncements,
        Inbound.CmsgChannelModerate
      ]

      Enum.each(modules, fn module ->
        assert %{channel_name: "Custom"} = module.from_binary(<<"Custom", 0>>)
      end)
    end

    test "parses channel and player commands" do
      modules = [
        Inbound.CmsgChannelSetOwner,
        Inbound.CmsgChannelModerator,
        Inbound.CmsgChannelUnmoderator,
        Inbound.CmsgChannelMute,
        Inbound.CmsgChannelUnmute,
        Inbound.CmsgChannelInvite,
        Inbound.CmsgChannelKick,
        Inbound.CmsgChannelBan,
        Inbound.CmsgChannelUnban
      ]

      Enum.each(modules, fn module ->
        assert %{channel_name: "Custom", player_name: "Player"} =
                 module.from_binary(<<"Custom", 0, "Player", 0>>)
      end)
    end

    test "parses channel passwords" do
      assert %Inbound.CmsgChannelPassword{channel_name: "Custom", password: "secret"} =
               Inbound.CmsgChannelPassword.from_binary(<<"Custom", 0, "secret", 0>>)
    end
  end
end
