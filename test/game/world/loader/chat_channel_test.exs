defmodule ThistleTea.Game.World.Loader.ChatChannelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.ChatChannel

  describe "resolve/2" do
    test "recognizes zone-dependent built-in channels" do
      definition = ChatChannel.resolve(ChatChannel.defaults(), "General - Elwynn Forest")
      assert definition.kind == {:builtin, 1}
      assert definition.flags == 0x18
    end

    test "recognizes built-in channels case-insensitively" do
      definition = ChatChannel.resolve(ChatChannel.defaults(), "worlddefense")
      assert definition.kind == {:builtin, 23}
    end

    test "classifies unknown channels as custom" do
      assert %{kind: :custom, flags: 0x01} = ChatChannel.resolve(ChatChannel.defaults(), "Thistle Tea")
    end
  end

  describe "load/0" do
    @tag :dbc_db
    test "loads built-in definitions from ChatChannels.dbc" do
      definitions = ChatChannel.load()
      assert %{kind: {:builtin, 1}, flags: 0x18} = ChatChannel.resolve(definitions, "General - Elwynn Forest")
    end
  end
end
