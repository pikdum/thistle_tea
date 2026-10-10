defmodule ThistleTea.Game.Core.Creature.LinkedFeignDeathTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Creature.LinkedFeignDeath
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Loot
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Power.Regen
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:hound]

  describe "prevent/4" do
    test "intercepts a template's one-health invincibility threshold", %{mob: mob, player: player} do
      mob = %{mob | internal: %{mob.internal | invincibility_health_threshold: 1}}
      fallen = Entity.take_damage(mob, 100_000, 1_000, source: player)

      assert fallen.unit.health == 1
      assert fallen.unit.stand_state == 7
      assert fallen.internal.linked_feign_death.revive_at == 11_000
    end

    test "intercepts exact lethal hits and overkill without finalizing a death", %{mob: mob, player: player} do
      for damage <- [100, 1_000] do
        fallen = Entity.take_damage(mob, damage, 1_000, source: player)

        assert fallen.unit.health == 1
        assert fallen.unit.stand_state == 7
        assert band(fallen.unit.dynamic_flags, 0x20) == 0x20
        assert fallen.internal.linked_feign_death.revive_at == 11_000
        assert fallen.internal.in_combat
        assert fallen.unit.target == player
        assert fallen.internal.loot.tapped_by == mob.internal.loot.tapped_by
        refute fallen.internal.killed_by
        refute fallen.internal.death_finalized?
        assert Enum.any?(fallen.internal.events, &match?(%Effects.AttackStop{}, &1))
        assert LinkedFeignDeath.active?(fallen)
      end
    end

    test "leaves nonlethal hits and ordinary creature deaths intact", %{mob: mob, player: player} do
      wounded = Entity.take_damage(mob, 99, 1_000, source: player)
      assert wounded.unit.health == 1
      refute LinkedFeignDeath.active?(wounded)

      ordinary = %{mob | internal: %{mob.internal | linked_feign_death: nil}}
      assert Entity.take_damage(ordinary, 100, 1_000, source: player).unit.health == 0
    end

    test "clears auras and protects the fallen pose from more damage, healing and regen", %{mob: mob, player: player} do
      spell = %Spell{id: Unique.integer(), effects: [%Effect{type: :apply_aura, aura: :mod_pacify}]}
      {mob, _} = Aura.apply_spell(mob, player, 60, spell, 0)
      fallen = Entity.take_damage(mob, 100, 1_000, source: player)

      assert fallen.unit.auras == []
      assert Entity.take_damage(fallen, 1_000, 2_000, source: player) == fallen
      assert Entity.heal(fallen, 100) == fallen
      refute Regen.needs_resource_regen?(fallen)
      assert Regen.tick(fallen, 2_000).unit.health == 1
      assert fallen.internal.linked_feign_death.revive_at == 11_000
    end

    test "scripted kills bypass prevention", %{mob: mob} do
      assert Entity.kill(mob, 1_000).unit.health == 0
    end
  end

  describe "tick/3" do
    test "waits ten seconds and revives at full health with a fighting peer", %{mob: mob, player: player} do
      fallen = Entity.take_damage(mob, 100, 1_000, source: player)
      context = context(fallen, player, 10_999, [%{health: 2, in_combat: true}])
      assert {{:running, 1, :feigned_death}, ^fallen, _} = tick(fallen, context)

      assert {:failure, revived, _} = tick(fallen, %{context | now: 11_000})
      assert revived.unit.health == 100
      assert revived.unit.stand_state == 0
      assert band(revived.unit.dynamic_flags, 0x20) == 0
      assert revived.unit.target == player
      assert revived.internal.threat == fallen.internal.threat
      refute LinkedFeignDeath.active?(revived)
      assert Enum.any?(revived.internal.events, &match?(%Effects.TriggerSpell{spell_id: 19_823}, &1))

      fallen_again = Entity.take_damage(revived, 100, 12_000, source: player)
      assert fallen_again.internal.linked_feign_death.revive_at == 22_000
    end

    test "dies and despawns when no fighting hound survives", %{mob: mob, player: player} do
      peers = [%{health: 1, in_combat: true}, %{health: 0, in_combat: true}, %{health: 100, in_combat: false}]
      fallen = Entity.take_damage(mob, 100, 1_000, source: player)
      assert {{:running, _, :dead}, dead, _} = tick(fallen, context(fallen, player, 11_000, peers))
      assert dead.unit.health == 0
      refute dead.internal.in_combat
      refute LinkedFeignDeath.active?(dead)
      assert Enum.any?(dead.internal.events, &match?(%Effects.DespawnSelf{duration_ms: 0}, &1))
    end

    test "ignores hounds outside the radius, in other copies and of other entries", %{mob: mob, player: player} do
      peers = [
        %{health: 100, in_combat: true, distance: 101},
        %{health: 100, in_combat: true, world: WorldRef.instance(409, Unique.integer())},
        %{health: 100, in_combat: true, entry: 11_672}
      ]

      fallen = Entity.take_damage(mob, 100, 1_000, source: player)
      assert {{:running, _, :dead}, dead, _} = tick(fallen, context(fallen, player, 11_000, peers))
      assert dead.unit.health == 0
    end

    test "restores a fallen hound after its opponents leave", %{mob: mob, player: player} do
      fallen = Entity.take_damage(mob, 100, 1_000, source: player)
      assert {:failure, restored, _} = tick(fallen, Context.new(2_000))
      assert restored.unit.health == 100
      assert restored.unit.stand_state == 0
      refute LinkedFeignDeath.active?(restored)
    end
  end

  describe "reset/3" do
    test "evading clears the timer and respawning accepts a new configuration", %{mob: mob, player: player} do
      fallen = Entity.take_damage(mob, 100, 1_000, source: player)
      assert %Engagement.Result{entity: restored} = Engagement.leave(fallen, :evade, 2_000)
      assert restored.unit.health == 100
      assert restored.unit.stand_state == 0
      refute restored.internal.in_combat
      refute LinkedFeignDeath.active?(restored)

      respawned = Mob.respawn(fallen)
      assert respawned.unit.health == 100
      assert respawned.unit.stand_state == 0
      assert respawned.internal.linked_feign_death == nil
      assert configure(respawned).internal.linked_feign_death.delay_ms == 10_000
    end
  end

  defp hound(_context) do
    player = Unique.integer()
    guid = Guid.from_low_guid(:mob, 11_671, Unique.integer())

    mob = %Mob{
      object: %Object{guid: guid, entry: 11_671},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 60,
        target: player,
        flags: 0,
        stand_state: 0,
        dynamic_flags: 4,
        auras: []
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(409, Unique.integer()),
        in_combat: true,
        threat: %{player => 10},
        loot: %Loot{tapped_by: %Engagement.Tap{player: player}},
        creature: %Creature{regenerate_stats: 3},
        spawn: %Spawn{position: {0.0, 0.0, 0.0}},
        blackboard: Blackboard.new()
      }
    }

    mob = %{mob | internal: %{mob.internal | spawn: %{mob.internal.spawn | unit: mob.unit}}}
    %{mob: configure(mob), player: player}
  end

  defp configure(mob) do
    [spawned | _] = CreatureScript.events(11_671)
    {mob, blackboard} = Script.run(mob, Blackboard.new(), List.flatten(spawned.actions), nil, 0)
    %{mob | internal: %{mob.internal | blackboard: blackboard}}
  end

  defp tick(mob, context), do: LinkedFeignDeath.tick(mob, mob.internal.blackboard, context)

  defp context(mob, player, now, peers) do
    world = mob.internal.world
    opponent = %Observation{guid: player, position: {world, 0.0, 0.0, 0.0}, metadata: %{alive?: true}}

    peers =
      Enum.map(peers, fn options ->
        guid = Guid.from_low_guid(:mob, Map.get(options, :entry, 11_671), Unique.integer())
        distance = Map.get(options, :distance, 5)
        position = {Map.get(options, :world, world), distance, 0.0, 0.0}
        {guid, %Observation{guid: guid, position: position, metadata: options}, distance}
      end)

    entities = Map.new(peers, fn {guid, observation, _distance} -> {guid, observation} end) |> Map.put(player, opponent)
    nearby = %{mobs: Enum.map(peers, fn {guid, _observation, distance} -> {guid, distance} end)}
    Context.new(now, perception: Perception.new(now, nil, entities, nearby))
  end
end
