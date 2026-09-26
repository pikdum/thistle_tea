defmodule ThistleTea.Game.Network.Message.CmsgCancelGrowthAuraTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.CmsgCancelGrowthAura
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "handle/2" do
    test "dispatches the empty notification without changing the player's scale" do
      state = %State{character: %Character{object: %Object{scale_x: 0.5}}}
      assert Dispatch.implemented?(0x29B)
      assert %CmsgCancelGrowthAura{} = message = Dispatch.to_message(%Packet{opcode: 0x29B, payload: <<>>})
      assert CmsgCancelGrowthAura.handle(message, state) == state
    end
  end
end
