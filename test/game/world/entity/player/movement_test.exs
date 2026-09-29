defmodule ThistleTea.Game.World.Entity.Player.MovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Environment.Breathing
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity.Player.Movement
  alias ThistleTea.Game.World.Entity.Player.State

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
