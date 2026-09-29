defmodule ThistleTea.Game.World.InboundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.World.Inbound

  describe "messages/0" do
    test "every decodable client message has a world handler" do
      assert Enum.reject(Dispatch.messages(), &Inbound.routed?/1) == []
    end

    test "every handled message is decodable" do
      assert Inbound.messages() -- Dispatch.messages() == []
    end
  end
end
