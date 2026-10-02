defmodule ThistleTea.Game.Inbound.CharacterPreferencesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Player.PlayedTime
  alias ThistleTea.Game.Core.Player.Tutorials
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgPlayedTime
  alias ThistleTea.Game.Inbound.CmsgToggleCloak
  alias ThistleTea.Game.Inbound.CmsgToggleHelm
  alias ThistleTea.Game.Inbound.CmsgTutorialClear
  alias ThistleTea.Game.Inbound.CmsgTutorialFlag
  alias ThistleTea.Game.Inbound.CmsgTutorialReset
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgPlayedTime
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.AccountDataStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Test.Unique

  describe "handle/2" do
    test "reports total and level time played without counting time before login" do
      played = %PlayedTime{total_ms: 7_200_000, level_ms: 600_000, since: Time.now() - 30_000}
      state = state(%Internal{played: played})

      assert Inbound.handle(%CmsgPlayedTime{}, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgPlayedTime{total: total, level: level}}}
      assert total in 7230..7232
      assert level in 630..632
    end

    test "toggles helm and cloak visibility in the player flags" do
      state = state(%Internal{})
      state = Inbound.handle(%CmsgToggleHelm{}, state)
      assert state.character.player.flags == 0x400
      state = Inbound.handle(%CmsgToggleCloak{}, state)
      assert state.character.player.flags == 0xC00
      assert Inbound.handle(%CmsgToggleHelm{}, state).character.player.flags == 0x800
    end

    test "remembers seen tutorials for the whole account" do
      state = state(%Internal{})
      account_id = state.account.id

      for {opcode, payload} <- [CMSG_TUTORIAL_FLAG: <<37::little-32>>, CMSG_TUTORIAL_CLEAR: <<>>] do
        assert %{} = Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload})
      end

      Inbound.handle(%CmsgTutorialFlag{index: 37}, state)
      assert AccountDataStore.tutorials(account_id) == Tutorials.mark(Tutorials.new(), 37)
      Inbound.handle(%CmsgTutorialClear{}, state)
      assert AccountDataStore.tutorials(account_id) == Tutorials.all_seen()
      Inbound.handle(%CmsgTutorialReset{}, state)
      assert AccountDataStore.tutorials(account_id) == Tutorials.new()
    end
  end

  defp state(internal) do
    guid = Unique.integer()
    {:ok, _owner} = Entity.register(guid)

    %State{
      ready: true,
      guid: guid,
      account: %{id: Unique.integer()},
      character: %Character{object: %Object{guid: guid}, player: %Player{flags: 0}, internal: internal}
    }
  end
end
