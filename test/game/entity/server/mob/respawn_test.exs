defmodule ThistleTea.Game.Entity.Server.Mob.RespawnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Server.Mob.Respawn
  alias ThistleTea.Game.WorldRef

  describe "schedule/1" do
    test "starts the respawn timer and stores the ref" do
      mob = fixture_mob(respawn_delay_ms: 5)

      scheduled = Respawn.schedule(mob)

      assert is_reference(scheduled.internal.spawn.respawn_ref)
      assert_receive :respawn, 100
    end

    test "does not reschedule while a timer is pending" do
      ref = make_ref()
      mob = fixture_mob(respawn_ref: ref)

      assert Respawn.schedule(mob).internal.spawn.respawn_ref == ref
      refute_receive :respawn, 10
    end
  end

  describe "handle/1" do
    test "clears the ref and kicks the AI loop when the mob is not dead" do
      mob = fixture_mob(health: 10, respawn_ref: make_ref())

      handled = Respawn.handle(mob)

      assert handled.internal.spawn.respawn_ref == nil
      assert_receive :ai_tick, 100
    end
  end

  describe "maybe_continue/1" do
    test "resumes a deferred respawn once nothing blocks it" do
      mob = fixture_mob(respawn_pending?: true)

      assert Respawn.maybe_continue(mob) == :ok
      assert_receive :respawn, 100
    end

    test "does nothing without a pending respawn" do
      mob = fixture_mob()

      assert Respawn.maybe_continue(mob) == :ok
      refute_receive :respawn, 10
    end
  end

  defp fixture_mob(opts \\ []) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        health: Keyword.get(opts, :health, 0),
        max_health: 10,
        level: 1
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        spawn: %Spawn{
          respawn_delay_ms: Keyword.get(opts, :respawn_delay_ms, 1_000),
          respawn_ref: Keyword.get(opts, :respawn_ref),
          respawn_pending?: Keyword.get(opts, :respawn_pending?, false)
        },
        loot: %Loot{}
      }
    }
  end
end
