defmodule ThistleTea.Game.World.Entity.CombatZoneTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.ZoneCombat
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Entity.CombatZone
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.ScriptExecution
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  setup [:world]

  describe "AIEnvironment.context/3" do
    test "captures distant dungeon members and pets while excluding other copies and charms", %{world: world, mob: mob} do
      player = put_actor(:players, world, 500.0)
      other = put_actor(:players, WorldRef.instance(world.map_id, world.instance_id + 1), 1.0)
      pet = put_actor(:mobs, world, 510.0, :pet)
      charmer = put_actor(:players, world, 600.0)
      charmed = put_actor(:mobs, world, 610.0, :mob)
      Metadata.update(player, %{controlled_guid: pet})
      Metadata.update(pet, %{owner_guid: player, pet_kind: :hunter})
      Metadata.update(charmer, %{controlled_guid: charmed})
      Metadata.update(charmed, %{owner_guid: charmer, pet_kind: :charmed})
      request = Request.for_script([%ScriptStep{command: :zone_combat_pulse, datalong: 1}])
      context = AIEnvironment.context(mob, 1_000, request)
      assert context.combat_zone.players == Enum.sort([player, charmer])
      assert context.combat_zone.pets == %{player => pet}
      assert Perception.position(context.perception, pet) == {world, 510.0, 0.0, 0.0}
      assert Perception.position(context.perception, other) == nil
      assert CombatZone.snapshot(mob, false) == nil
      assert CombatZone.snapshot(put_in(mob.internal.world, WorldRef.open(0)), true) == nil
    end

    test "pulse and reset deliver incarnation-scoped combat references to every admitted owner", %{
      world: world,
      mob: mob
    } do
      player = put_actor(:players, world, 10.0)
      pet = put_actor(:mobs, world, 20.0, :pet)
      Metadata.update(player, %{controlled_guid: pet})
      Metadata.update(pet, %{owner_guid: player, pet_kind: :summon})
      Entity.register(player)
      Entity.register(pet)
      request = Request.for_script([%ScriptStep{command: :zone_combat_pulse, datalong: 1}])
      context = AIEnvironment.context(mob, 1_000, request)
      fighting = mob |> ZoneCombat.pulse(true, context) |> EventSink.emit_pending()
      guid = mob.object.guid
      assert_receive {:"$gen_cast", {:threat_ref_gained, ^guid, 123}}
      assert_receive {:"$gen_cast", {:threat_ref_gained, ^guid, 123}}
      refute_receive {:"$gen_cast", {:threat_ref_gained, ^guid, 123}}, 20
      assert fighting.internal.threat == %{player => 0.0, pet => 0.0}
      stopped = Engagement.leave(fighting, :evade).entity |> EventSink.emit_pending()
      assert_receive {:"$gen_cast", {:threat_ref_lost, ^guid, 123}}
      assert_receive {:"$gen_cast", {:threat_ref_lost, ^guid, 123}}
      assert stopped.internal.combat_zone == nil
    end

    test "remote script receipts request their own fresh dungeon snapshot", %{world: world, mob: mob} do
      player = put_actor(:players, world, 500.0)

      request = %ThistleTea.Game.Core.AI.Script.Request{
        step: %ScriptStep{command: :zone_combat_pulse, datalong: 1},
        target_guid: player,
        world: world,
        reply_to: self(),
        id: 1,
        deadline: ThistleTea.Game.Core.Time.now() + 10_000
      }

      result = ScriptExecution.command(mob, request)
      assert result.unit.target == player
      assert result.internal.combat_zone != nil
    end
  end

  defp world(_context) do
    map = 995
    previous = :ets.lookup(MapTemplate, map)
    :ets.insert(MapTemplate, {map, 1, nil})
    world = WorldRef.instance(map, System.unique_integer([:positive, :monotonic]))
    guid = Guid.runtime(:mob, 1)

    mob = %Mob{
      object: %Object{guid: guid, entry: 1},
      unit: %Unit{health: 100, max_health: 100, level: 20, flags: 0, faction_template: 17},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: world,
        in_combat: false,
        blackboard: Blackboard.new(),
        creature: %Creature{},
        spawn: %Spawn{incarnation_id: 123, position: {0.0, 0.0, 0.0}}
      }
    }

    Metadata.put(guid, %{
      alive?: true,
      faction_template: %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
    })

    on_exit(fn ->
      :ets.delete(MapTemplate, map)
      :ets.insert(MapTemplate, previous)
      Metadata.delete(guid)
    end)

    %{world: world, mob: mob}
  end

  defp put_actor(table, world, x, kind \\ :player) do
    guid =
      if kind == :player,
        do: Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic])),
        else: Guid.runtime(kind, 1)

    SpatialHash.update(table, guid, world, x, 0.0, 0.0)

    Metadata.put(guid, %{
      alive?: true,
      in_combat: false,
      faction_template: %FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}
    })

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)

    guid
  end
end
