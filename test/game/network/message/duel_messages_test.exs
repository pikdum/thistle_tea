defmodule ThistleTea.Game.Network.Message.DuelMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgDuelAccepted
  alias ThistleTea.Game.Network.Message.CmsgDuelCancelled
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgDuelComplete
  alias ThistleTea.Game.Network.Message.SmsgDuelCountdown
  alias ThistleTea.Game.Network.Message.SmsgDuelInbounds
  alias ThistleTea.Game.Network.Message.SmsgDuelOutofbounds
  alias ThistleTea.Game.Network.Message.SmsgDuelRequested
  alias ThistleTea.Game.Network.Message.SmsgDuelWinner
  alias ThistleTea.Game.Network.Opcodes

  describe "client codecs" do
    test "decode the duel arbiter guid" do
      player_guid = 0x0102030405060708
      payload = <<player_guid::little-size(64)>>

      assert CmsgDuelAccepted.from_binary(payload) == %CmsgDuelAccepted{player_guid: player_guid}
      assert CmsgDuelCancelled.from_binary(payload) == %CmsgDuelCancelled{player_guid: player_guid}
      assert Dispatch.implemented?(Opcodes.get(:CMSG_DUEL_ACCEPTED))
      assert Dispatch.implemented?(Opcodes.get(:CMSG_DUEL_CANCELLED))
    end
  end

  describe "server codecs" do
    test "encode requests and countdowns" do
      assert SmsgDuelRequested.to_binary(%SmsgDuelRequested{arbiter_guid: 11, initiator_guid: 22}) ==
               <<11::little-size(64), 22::little-size(64)>>

      assert SmsgDuelCountdown.to_binary(%SmsgDuelCountdown{time_ms: 3_000}) ==
               <<3_000::little-size(32)>>
    end

    test "encode bound transitions and completion" do
      assert SmsgDuelOutofbounds.to_binary(%SmsgDuelOutofbounds{}) == <<>>
      assert SmsgDuelInbounds.to_binary(%SmsgDuelInbounds{}) == <<>>
      assert SmsgDuelComplete.to_binary(%SmsgDuelComplete{started?: false}) == <<0>>
      assert SmsgDuelComplete.to_binary(%SmsgDuelComplete{started?: true}) == <<1>>
    end

    test "encodes winner names and fled reason" do
      assert SmsgDuelWinner.to_binary(%SmsgDuelWinner{
               fled?: true,
               winner_name: "Winner",
               loser_name: "Loser"
             }) == <<1, "Winner", 0, "Loser", 0>>
    end
  end
end
