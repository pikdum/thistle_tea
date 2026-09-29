defmodule ThistleTea.Game.Network.Message.CmsgCancelGrowthAuraTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Network.Message.CmsgCancelGrowthAura
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Inbound

  describe "handle/2" do
    test "dispatches the empty notification without changing the player's scale" do
      state = %State{character: %Character{object: %Object{scale_x: 0.5}}}
      assert Dispatch.implemented?(0x29B)
      assert %CmsgCancelGrowthAura{} = message = Dispatch.to_message(%Packet{opcode: 0x29B, payload: <<>>})
      assert Inbound.handle(message, state) == state
    end
  end
end
