defmodule ThistleTea.Game.Player.MovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Time

  describe "publish_changes/1" do
    test "shortens an existing aura wake when movement starts a breath timer" do
      now = Time.now()
      ref = Process.send_after(self(), :player_tick, 40_000)
      character = character(now)
      state = Movement.publish_changes(%State{character: character, player_tick_ref: ref})
      refute state.player_tick_ref == ref
      refute Process.read_timer(ref)
      assert Process.read_timer(state.player_tick_ref) <= 1000
      Process.cancel_timer(state.player_tick_ref)
    end

    test "drains timer effects and wakes an idle owner without a unit field change" do
      character = character(Time.now())
      effect = %Effects.StartMirrorTimer{timer: 1, remaining: 60_000, duration: 60_000, scale: -1}
      character = %{character | internal: %{character.internal | events: [effect]}}
      state = Movement.publish_changes(%State{character: character})
      assert state.character.internal.events == []
      assert is_reference(state.player_tick_ref)
      assert_receive :player_tick
    end
  end

  defp character(now) do
    %Character{
      object: %Object{guid: 99_999_998},
      player: %Player{},
      unit: %Unit{health: 100, max_health: 100, auras: [%Holder{expires_at: now + 40_000}]},
      internal: %Internal{breath: %Breathing{remaining: 60_000, duration: 60_000, updated_at: now}}
    }
  end
end
