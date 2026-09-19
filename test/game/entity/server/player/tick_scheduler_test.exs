defmodule ThistleTea.Game.Entity.Server.Player.TickSchedulerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Time

  describe "ensure_scheduled/1" do
    test "wakes for a shortened aura before the original expiry" do
      ref = Process.send_after(self(), :player_tick, 40_000)
      character = character([%Holder{expires_at: Time.now() + 50}])

      state = TickScheduler.ensure_scheduled(%{character: character, player_tick_ref: ref})

      refute state.player_tick_ref == ref
      refute Process.read_timer(ref)
      assert_receive :player_tick, 1_000
    end

    test "preserves an earlier behavior wake when the aura expires later" do
      ref = Process.send_after(self(), :player_tick, 1_000)
      state = %{character: character([%Holder{expires_at: Time.now() + 40_000}]), player_tick_ref: ref}

      assert TickScheduler.ensure_scheduled(state) == state
      Process.cancel_timer(ref)
    end

    test "wakes for newly needed regeneration before an existing aura timer" do
      now = Time.now()
      character = character([%Holder{expires_at: now + 40_000}])

      character = %{
        character
        | unit: %{character.unit | health: 50},
          internal: %{
            character.internal
            | blackboard: %Blackboard{maintenance: %Blackboard.Maintenance{next_regen_at: now + 50}}
          }
      }

      ref = Process.send_after(self(), :player_tick, 40_000)
      state = TickScheduler.ensure_scheduled(%{character: character, player_tick_ref: ref})

      refute state.player_tick_ref == ref
      refute Process.read_timer(ref)
      assert_receive :player_tick, 1_000
    end

    test "leaves an already delivered tick to run" do
      ref = Process.send_after(self(), :player_tick, 0)
      assert_receive :player_tick
      state = %{character: character([%Holder{expires_at: Time.now() + 10_000}]), player_tick_ref: ref}

      assert TickScheduler.ensure_scheduled(state) == state
    end

    test "schedules hidden mana recovery before a long form aura timer" do
      now = Time.now()
      character = character([%Holder{expires_at: now + 40_000}])

      character = %{
        character
        | unit: %{character.unit | power_type: 3, power1: 50, power4: 100, max_power4: 100},
          internal: %{
            character.internal
            | blackboard: %Blackboard{maintenance: %Blackboard.Maintenance{next_regen_at: now + 50}}
          }
      }

      ref = Process.send_after(self(), :player_tick, 40_000)
      state = TickScheduler.ensure_scheduled(%{character: character, player_tick_ref: ref})

      refute state.player_tick_ref == ref
      refute Process.read_timer(ref)
      assert_receive :player_tick, 1_000
    end

    test "starts ticking active auras but leaves idle characters asleep" do
      idle = %{character: character([]), player_tick_ref: nil}
      assert TickScheduler.ensure_scheduled(idle) == idle

      active = %{idle | character: character([%Holder{expires_at: Time.now() + 10_000}])}
      assert is_reference(TickScheduler.ensure_scheduled(active).player_tick_ref)
      assert_receive :player_tick
    end
  end

  defp character(auras) do
    %Character{
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, auras: auras},
      internal: %Internal{}
    }
  end
end
