defmodule ThistleTea.Game.Network.Message.MirrorTimerMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message.SmsgStartMirrorTimer
  alias ThistleTea.Game.Network.Message.SmsgStopMirrorTimer

  describe "to_binary/1" do
    test "encodes a signed countdown scale in the vanilla layout" do
      message = %SmsgStartMirrorTimer{timer: 1, remaining: 30_000, duration: 60_000, scale: -1}
      assert SmsgStartMirrorTimer.opcode() == 0x1D9

      assert SmsgStartMirrorTimer.to_binary(message) ==
               <<1::little-32, 30_000::little-32, 60_000::little-32, 0xFFFFFFFF::little-32, 0, 0::little-32>>

      assert SmsgStopMirrorTimer.opcode() == 0x1DB
      assert SmsgStopMirrorTimer.to_binary(%SmsgStopMirrorTimer{timer: 1}) == <<1::little-32>>
    end
  end

  describe "emit/3" do
    test "delivers timer changes to the explicitly supplied owner" do
      character = %Character{}
      context = Context.new(self())
      start = %Effects.StartMirrorTimer{timer: 1, remaining: 30_000, duration: 60_000, scale: 10}
      assert ClientProjection.emit(character, start, context) == character
      assert_receive {:"$gen_cast", {:send_packet, %SmsgStartMirrorTimer{timer: 1, scale: 10}}}
      assert ClientProjection.emit(character, %Effects.StopMirrorTimer{timer: 1}, context) == character
      assert_receive {:"$gen_cast", {:send_packet, %SmsgStopMirrorTimer{timer: 1}}}
    end
  end
end
