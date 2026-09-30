defmodule ThistleTea.Game.Inbound.CmsgCancelGrowthAuraTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgCancelGrowthAura
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.Entity.Player.State

  describe "handle/2" do
    test "dispatches the empty notification without changing the player's scale" do
      state = %State{character: %Character{object: %Object{scale_x: 0.5}}}
      assert Dispatch.implemented?(0x29B)
      assert %CmsgCancelGrowthAura{} = message = Dispatch.to_message(%Packet{opcode: 0x29B, payload: <<>>})
      assert Inbound.handle(message, state) == state
    end
  end
end
