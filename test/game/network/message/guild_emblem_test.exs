defmodule ThistleTea.Game.Network.Message.GuildEmblemTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes

  describe "from_binary/1" do
    test "decodes tabard activation and the five emblem fields" do
      assert Dispatch.implemented?(Opcodes.get(:MSG_TABARDVENDOR_ACTIVATE))
      assert Dispatch.implemented?(Opcodes.get(:MSG_SAVE_GUILD_EMBLEM))

      assert %Message.MsgTabardvendorActivateClient{vendor_guid: 42} =
               Message.MsgTabardvendorActivateClient.from_binary(<<42::little-size(64)>>)

      assert %Message.MsgSaveGuildEmblemClient{vendor_guid: 42, emblem: {1, 2, 3, 4, 5}} =
               Message.MsgSaveGuildEmblemClient.from_binary(
                 <<42::little-size(64), 1::little-size(32), 2::little-size(32), 3::little-size(32), 4::little-size(32),
                   5::little-size(32)>>
               )
    end
  end

  describe "to_binary/1" do
    test "encodes the tabard vendor and result opcodes" do
      assert Message.MsgTabardvendorActivateServer.to_binary(%Message.MsgTabardvendorActivateServer{vendor_guid: 42}) ==
               <<42::little-size(64)>>

      assert Message.MsgSaveGuildEmblemServer.to_binary(%Message.MsgSaveGuildEmblemServer{result: :ok}) ==
               <<0::little-size(32)>>

      assert Message.MsgSaveGuildEmblemServer.to_binary(%Message.MsgSaveGuildEmblemServer{result: :not_enough_money}) ==
               <<4::little-size(32)>>
    end
  end
end
