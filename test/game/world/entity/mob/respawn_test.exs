defmodule ThistleTea.Game.World.Entity.Mob.RespawnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Combat.CombatLeash
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Loot
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Mob.Respawn
  alias ThistleTea.Game.World.System.CombatLeashes
  alias ThistleTea.Test.Unique

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

  describe "summon_despawn_due/1" do
    test "waits while the summon is charm-controlled" do
      mob = fixture_mob(health: 10, despawn_type: 3, pet: %Pet{owner_guid: 5, kind: :charmed})

      assert Respawn.summon_despawn_due(mob) == :wait
    end

    test "waits out combat for out-of-combat despawn types" do
      assert Respawn.summon_despawn_due(fixture_mob(health: 10, despawn_type: 1, in_combat: true)) == :wait
      assert Respawn.summon_despawn_due(fixture_mob(health: 10, despawn_type: 1)) == :despawn
      assert Respawn.summon_despawn_due(fixture_mob(health: 10, despawn_type: 3, in_combat: true)) == :despawn
    end

    test "leaves a timed-or-dead corpse to decay" do
      assert Respawn.summon_despawn_due(fixture_mob(despawn_type: 1)) == :ignore
      assert Respawn.summon_despawn_due(fixture_mob(despawn_type: 3)) == :despawn
    end

    test "despawns untyped summons when their timer ends" do
      assert Respawn.summon_despawn_due(fixture_mob(health: 10, in_combat: true)) == :despawn
    end

    test "does not hold owned pets that are not charmed" do
      mob = fixture_mob(health: 10, despawn_type: 3, pet: %Pet{owner_guid: 5, kind: :summon})

      assert Respawn.summon_despawn_due(mob) == :despawn
    end
  end

  describe "schedule/1 for a typed summon" do
    test "keeps a timed-or-dead corpse without a respawn timer" do
      scheduled = Respawn.schedule(fixture_mob(temporary?: true, despawn_type: 1, despawn_delay_ms: 5))

      assert scheduled.internal.spawn.respawn_ref == nil
      assert scheduled.internal.spawn.despawn_ref == nil
      refute_receive :respawn, 20
    end

    test "starts an out-of-combat summon's timer over at death" do
      scheduled = Respawn.schedule(fixture_mob(temporary?: true, despawn_type: 4, despawn_delay_ms: 5))
      ref = scheduled.internal.spawn.despawn_ref

      assert is_reference(ref)
      assert_receive {:summon_despawn, ^ref}, 100
    end
  end

  describe "despawn/2" do
    test "ends the engagement and releases its shared clock before hiding the corpse" do
      mob = fixture_mob(health: 10)
      guid = Guid.from_low_guid(:mob, 1, Unique.integer())
      {:ok, _} = Entity.register(guid)
      on_exit(fn -> Entity.unregister(guid) end)
      mob = %{mob | object: %{mob.object | guid: guid}}
      %{entity: mob} = Engagement.enter(mob, 20, 1_000, selection: :target)
      mob = EventSink.emit_pending(mob)
      ref = CombatLeash.reference(mob)
      assert CombatLeashes.last_extended_at(ref) == 1_000
      mob = Respawn.despawn(mob, 60_000)
      refute mob.internal.in_combat
      assert mob.unit.health == 0
      assert mob.unit.target == 0
      assert mob.internal.threat == %{}
      assert mob.internal.loot.corpse_removed?
      assert CombatLeashes.last_extended_at(ref) == nil
      Process.cancel_timer(mob.internal.spawn.respawn_ref)
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
        in_combat: Keyword.get(opts, :in_combat, false),
        pet: Keyword.get(opts, :pet),
        spawn: %Spawn{
          respawn_delay_ms: Keyword.get(opts, :respawn_delay_ms, 1_000),
          respawn_ref: Keyword.get(opts, :respawn_ref),
          respawn_pending?: Keyword.get(opts, :respawn_pending?, false),
          despawn_type: Keyword.get(opts, :despawn_type),
          despawn_delay_ms: Keyword.get(opts, :despawn_delay_ms),
          temporary?: Keyword.get(opts, :temporary?, false)
        },
        loot: %Loot{}
      }
    }
  end
end
