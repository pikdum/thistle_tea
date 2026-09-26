defmodule ThistleTea.Game.Entity.Server.Mob.SummonLifecycleTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Guardian
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Data.SummonEvent
  alias ThistleTea.Game.Entity.Server.Mob.SummonLifecycle
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:summoner]

  describe "summon lifecycle" do
    test "NPC pets grant one reward and leave an unlootable corpse until removal", %{summoner: summoner} do
      killer = System.unique_integer([:positive]) + 10_000_000
      Entity.register(killer)

      for kind <- [:creature_pet, :guardian] do
        mob = mob(summoner)
        guid = Guid.runtime(:pet, mob.object.entry)

        mob = %{
          mob
          | object: %{mob.object | guid: guid},
            internal: %{mob.internal | pet: %Pet{owner_guid: summoner, kind: kind, profile: :combat}}
        }

        {:ok, pid} = start(mob)
        kill(guid, killer)
        assert_receive {:"$gen_cast", {:reward_kill, %Mob{object: %{guid: ^guid}} = victim}}
        assert victim.unit.health == 0
        assert victim.internal.death_finalized?
        assert victim.internal.loot.tapped_by == nil
        assert victim.internal.loot.session == nil
        assert victim.internal.spawn.respawn_ref == nil
        assert Process.alive?(pid)
        kill(guid, killer)
        assert :sys.get_state(pid).internal.death_finalized?
        refute_receive {:"$gen_cast", {:reward_kill, _}}
        monitor = Process.monitor(pid)
        send(pid, :pet_stop)
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
        assert Metadata.get(guid) == nil
        assert World.position(guid) == nil
      end
    end

    test "player-owned pets grant no kill credit", %{summoner: summoner} do
      killer = System.unique_integer([:positive]) + 10_000_000
      Entity.register(killer)
      mob = mob(summoner)
      guid = Guid.runtime(:pet, mob.object.entry)

      mob = %{
        mob
        | object: %{mob.object | guid: guid},
          internal: %{mob.internal | pet: %Pet{owner_guid: killer + 1, kind: :guardian, profile: :combat}}
      }

      {:ok, pid} = start(mob)
      kill(guid, killer)
      assert :sys.get_state(pid).unit.health == 0
      refute_receive {:"$gen_cast", {:reward_kill, _}}
    end

    test "temporary creatures publish one birth, death, and corpse departure", %{summoner: summoner} do
      mob = mob(summoner)
      guid = mob.object.guid
      {:ok, pid} = start(mob)
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_unit, observation: %{guid: ^guid}}}
      kill(guid)
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_died, observation: dead}}
      assert dead.metadata.alive? == false
      assert dead.metadata.health_pct == 0
      kill(guid)
      dead_state = :sys.get_state(pid)
      assert dead_state.internal.death_finalized?
      refute_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_died}}
      refute_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_despawn}}
      monitor = Process.monitor(pid)
      send(pid, {:remove_corpse, dead_state.internal.loot.corpse_token})
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1000
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_despawn, observation: departed}} = message
      assert departed.metadata.alive? == false
      assert World.position(guid) == nil
      assert Metadata.get(guid) == nil
      refute_receive ^message
    end

    test "timed removal of a living summon does not report death", %{summoner: summoner} do
      mob = mob(summoner)
      mob = %{mob | internal: %{mob.internal | spawn: %{mob.internal.spawn | despawn_type: 3, despawn_delay_ms: 100}}}
      {:ok, pid} = start(mob)
      monitor = Process.monitor(pid)
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_unit}}
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1000
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_despawn, observation: departed}}
      assert departed.metadata.alive?
      refute_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_died}}
    end

    test "totems and pets use the same death edge before shutdown", %{summoner: summoner} do
      for kind <- [:totem, :guardian] do
        mob = mob(summoner)

        internal =
          case kind do
            :totem -> %{mob.internal | totem: %Totem{owner_guid: summoner, expires_at: Time.now() + 60_000}}
            :guardian -> %{mob.internal | pet: %Pet{owner_guid: summoner, kind: :guardian, profile: :combat}}
          end

        mob = %{mob | internal: internal}
        {:ok, _pid} = start(mob)
        assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_unit}}
        kill(mob.object.guid)
        assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_died}}
        World.stop_entity(mob.object.guid)
        assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_despawn}}
      end
    end

    test "a removed summon retains condition facts and cannot trigger another copy", %{summoner: summoner} do
      summon = mob(summoner)
      {:ok, _pid} = start(summon)
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_unit}}
      World.stop_entity(summon.object.guid)
      assert_receive {:"$gen_cast", %SummonEvent{event: :summoned_just_despawn} = event}
      assert Metadata.get(summon.object.guid) == nil

      trigger = %AIEvent{
        event_type: :summoned_just_despawn,
        param1: summon.object.entry,
        condition: %Condition{type: :alive},
        actions: [[%ScriptStep{command: :set_phase, datalong: 3}]]
      }

      owner = mob(nil)
      owner = %{owner | internal: %{owner.internal | creature: %{owner.internal.creature | ai_events: [trigger]}}}
      applied = SummonLifecycle.receive_event(owner, event, Time.now())
      assert applied.internal.blackboard.event_ai.phase == 3
      foreign = %{event | world: WorldRef.instance(998, 2)}
      assert SummonLifecycle.receive_event(owner, foreign, Time.now()) == owner
    end
  end

  defp summoner(_context) do
    summoner = Guid.runtime(:mob, 990_401)
    Entity.register(summoner)
    %{summoner: summoner}
  end

  defp start(mob) do
    mob = prepare_owner(mob)
    on_exit(fn -> World.stop_entity(mob.object.guid) end)
    World.start_entity(mob)
  end

  defp prepare_owner(%Mob{internal: %{pet: %Pet{owner_guid: owner, kind: kind}}} = mob) do
    table = if Guid.entity_type(owner) == :player, do: :players, else: :mobs
    Metadata.put(owner, %{alive?: true, pet_guid: mob.object.guid})
    SpatialHash.update(table, owner, mob.internal.world, 0.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(owner)
      SpatialHash.remove(table, owner)
    end)

    if kind == :guardian, do: %{mob | internal: %{mob.internal | guardian: %Guardian{}}}, else: mob
  end

  defp prepare_owner(mob), do: mob

  defp kill(guid, caster \\ nil) do
    spell = %Spell{id: 5, effects: [%Effect{index: 0, type: :instakill}]}
    Entity.receive_spell(guid, %CastContext{caster_guid: caster || guid, caster_level: 20}, spell)
  end

  defp mob(summoner) do
    %Mob{
      object: %Object{guid: Guid.runtime(:mob, 990_402), entry: 990_402},
      unit: %Unit{health: 100, max_health: 100, level: 20, faction_template: 14, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(998, 1),
        creature: %Creature{stationary?: true},
        spawn: %Spawn{temporary?: true, despawn_type: 7, summoner_guid: summoner},
        loot: %Loot{},
        spellbook: %{}
      }
    }
  end
end
