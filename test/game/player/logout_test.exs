defmodule ThistleTea.Game.Player.LogoutTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Aura.MovementSync
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Logout, as: LogoutLogic
  alias ThistleTea.Game.Entity.Logic.Rest
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Logout
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Spell

  setup [:player_state]

  describe "admission/1" do
    test "uses immediate logout in rest areas and on flights", %{state: state} do
      for location <- [:city, {:tavern, 71}] do
        assert LogoutLogic.admission(Rest.start(state.character, location, 0)) == {:ok, :instant}
      end

      flying = %{state.character | internal: %{state.character.internal | taxi_flight: %{}}}
      assert LogoutLogic.admission(flying) == {:ok, :instant}
      assert LogoutLogic.admission(state.character) == {:ok, :delayed}
    end

    test "rejects combat, airborne movement, and GM freeze before instant logout", %{state: state} do
      resting = Rest.start(state.character, :city, 0)
      assert LogoutLogic.admission(put_in(resting.internal.in_combat, true)) == {:error, :failure_in_combat}

      for flags <- [0x2000, 0x4000] do
        assert LogoutLogic.admission(put_in(resting.movement_block.movement_flags, flags)) ==
                 {:error, :failure_jumping_or_falling}
      end

      frozen = put_in(resting.unit.auras, [%Holder{spell: %Spell{id: 9454}}])
      assert LogoutLogic.admission(frozen) == {:error, :failure_frozen_by_gm}
    end
  end

  describe "start/2 and cancel/2" do
    test "sits and immobilizes the player and restores movement on cancellation", %{state: state} do
      waiting = LogoutLogic.start(state.character, 0)
      assert waiting.unit.stand_state == 1
      assert waiting.internal.logout == :rooted
      assert waiting.internal.rooted?
      assert band(waiting.unit.flags, 0x40000) != 0
      assert band(waiting.player.field_bytes_flags, 4) != 0
      refute Movement.accepts_input?(waiting)
      EventSink.emit_pending(waiting, Context.new(self()))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgForceMoveRoot{}}}

      cancelled = LogoutLogic.cancel(%{waiting | internal: %{waiting.internal | events: []}}, 10_000)
      assert cancelled.unit.stand_state == 0
      assert cancelled.internal.logout == nil
      refute cancelled.internal.rooted?
      assert band(cancelled.unit.flags, 0x40000) == 0
      assert cancelled.player.field_bytes_flags == state.character.player.field_bytes_flags
      assert Movement.accepts_input?(cancelled)
      assert %Effects.MovementRootChanged{rooted?: false} in cancelled.internal.events
    end

    test "aura recomputation preserves the logout restriction", %{state: state} do
      waiting = LogoutLogic.start(state.character, 0)
      {changed, events} = MovementSync.sync_movement_state(waiting, 1_000)
      assert changed.internal.rooted?
      assert band(changed.unit.flags, 0x40000) != 0
      refute %Effects.MovementRootChanged{rooted?: false} in events
    end

    test "cancel retains roots and stuns applied during the countdown", %{state: state} do
      for type <- [:mod_root, :mod_stun] do
        waiting = LogoutLogic.start(state.character, 0)
        aura = %Holder{spell: %Spell{id: 1}, auras: [%Aura{type: type}]}
        waiting = %{waiting | unit: %{waiting.unit | auras: [aura]}, internal: %{waiting.internal | events: []}}
        cancelled = LogoutLogic.cancel(waiting, 1_000)
        assert cancelled.internal.rooted?
        refute %Effects.MovementRootChanged{rooted?: false} in cancelled.internal.events
        assert band(cancelled.unit.flags, 0x40000) != 0 == (type == :mod_stun)
      end
    end

    test "cancel does not release the death root", %{state: state} do
      waiting = LogoutLogic.start(state.character, 0)
      dead = %{waiting | unit: %{waiting.unit | health: 0}, internal: %{waiting.internal | events: []}}
      cancelled = LogoutLogic.cancel(dead, 1_000)
      assert cancelled.internal.rooted?
      refute %Effects.MovementRootChanged{rooted?: false} in cancelled.internal.events
    end

    test "does not force a sitting pose while mounted or swimming", %{state: state} do
      mounted = %{state.character | unit: %{state.character.unit | mount_display_id: 123}}
      swimming = %{state.character | movement_block: %{state.character.movement_block | movement_flags: 0x200000}}

      for character <- [mounted, swimming] do
        assert LogoutLogic.start(character, 0).unit.stand_state == 0
      end
    end
  end

  describe "request/1 and cancel/1" do
    test "late packets after the player leaves keep the character-selection connection alive" do
      connection = %ConnectionState{player_pid: nil, player_monitor: nil}
      assert Message.CmsgLogoutCancel.handle(%Message.CmsgLogoutCancel{}, connection) == connection
      assert Message.CmsgLogoutRequest.handle(%Message.CmsgLogoutRequest{}, connection) == connection
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgLogoutCancelAck{}}}
    end

    test "schedules twenty seconds and starts offline rest only on world departure", %{state: state} do
      waiting = Message.CmsgLogoutRequest.handle(%Message.CmsgLogoutRequest{}, state)
      assert Process.read_timer(waiting.logout_timer.ref) in 19_000..20_000
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLogoutResponse{result: 0, speed: 0}}}
      assert waiting.character.internal.rest_logout_at == nil
      cancelled = Message.CmsgLogoutCancel.handle(%Message.CmsgLogoutCancel{}, waiting)
      assert cancelled.logout_timer == nil
      assert cancelled.character.internal.rest_logout_at == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLogoutCancelAck{}}}
      assert Process.read_timer(waiting.logout_timer.ref) == false

      assert {:noreply, ^cancelled} =
               PlayerServer.handle_info({:logout_complete, waiting.logout_timer.token}, cancelled)
    end

    test "repeated requests replace the timer without accepting the previous token", %{state: state} do
      first = Logout.request(state)
      second = Logout.request(first)
      refute first.logout_timer.token == second.logout_timer.token
      assert Process.read_timer(first.logout_timer.ref) == false
      assert {:noreply, ^second} = PlayerServer.handle_info({:logout_complete, first.logout_timer.token}, second)
      Logout.cancel(second)
    end

    test "rejection cancels an existing countdown", %{state: state} do
      waiting = Logout.request(state)
      rejected = Logout.request(put_in(waiting.character.internal.in_combat, true))
      assert rejected.logout_timer == nil
      assert rejected.character.internal.logout == nil
      assert Process.read_timer(waiting.logout_timer.ref) == false
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLogoutResponse{result: 1, speed: 0}}}
    end

    test "rest areas return the native instant response", %{state: state} do
      state = %{state | character: Rest.start(state.character, :city, 0)}
      waiting = Logout.request(state)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLogoutResponse{result: 0, speed: 1}}}
      token = waiting.logout_timer.token
      assert_receive {:logout_complete, ^token}
      assert waiting.character.internal.logout == nil
      Logout.clear(waiting)
    end
  end

  defp player_state(_context) do
    guid = System.unique_integer([:positive])

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, flags: 0, stand_state: 0, auras: []},
      player: %Player{flags: 0, field_bytes_flags: 8, next_level_xp: 1000},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    %{state: %State{guid: guid, character: character}}
  end
end
