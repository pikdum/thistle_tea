defmodule ThistleTea.Game.Entity.Server.Mob.ChargeAttackTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "handle_info/2" do
    test "arrival enters the shared engagement lifecycle", %{creature: creature, target: target} do
      assert {:noreply, started, {:continue, :maybe_broadcast}} =
               MobServer.handle_info({:force_attack, target}, creature)

      assert started.internal.in_combat
      assert started.unit.target == target.guid
      assert is_reference(started.internal.ai_tick_ref)
      Process.cancel_timer(started.internal.ai_tick_ref)
    end

    test "target death, respawn and world changes prevent arrival combat", %{creature: creature, target: target} do
      metadata = Metadata.get(target.guid)

      for changed <- [%{metadata | alive?: false}, %{metadata | incarnation_id: 8}] do
        Metadata.put(target.guid, changed)
        assert {:noreply, ^creature} = MobServer.handle_info({:force_attack, target}, creature)
      end

      Metadata.put(target.guid, metadata)
      SpatialHash.update(:mobs, target.guid, WorldRef.instance(0, 99), 1.0, 0.0, 0.0)
      assert {:noreply, ^creature} = MobServer.handle_info({:force_attack, target}, creature)
    end
  end

  defp entities(_context) do
    guid = Guid.runtime(:mob, 1)
    target_guid = Guid.runtime(:mob, 2)
    alliance = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}

    wolf = %FactionTemplate{
      id: 32,
      faction: 29,
      flags: 16,
      faction_group: 0,
      friend_group: 0,
      enemy_group: 2,
      enemies_0: 28
    }

    Metadata.put(guid, %{faction_template: alliance, alive?: true})
    Metadata.put(target_guid, %{faction_template: wolf, alive?: true, incarnation_id: 7, unit_flags: 0})
    SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(guid)
      Metadata.delete(target_guid)
      SpatialHash.remove(:mobs, target_guid)
    end)

    creature = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{creature: creature, target: %TargetRef{guid: target_guid, incarnation_id: 7}}
  end
end
