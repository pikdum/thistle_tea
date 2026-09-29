defmodule ThistleTea.Game.Core.Combat.ZoneCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.CombatZone
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.AI.Tick
  alias ThistleTea.Game.Core.AI.TickPlan
  alias ThistleTea.Game.Core.Combat.CombatZone, as: State
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.Threat
  alias ThistleTea.Game.Core.Combat.ZoneCombat
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  setup [:creature]

  describe "pulse/3" do
    test "starts on the nearest hostile player and enrolls distant players and their pets", %{mob: mob} do
      pet = Guid.from_low_guid(:pet, 1, 7)
      context = context(mob, [{1, 700.0, %{}}, {2, 10.0, %{}}, {pet, 710.0, %{owner_guid: 1}}], %{1 => pet})
      result = ZoneCombat.pulse(mob, true, context)
      assert result.unit.target == 2
      assert result.internal.in_combat
      assert result.internal.threat == %{1 => 0.0, 2 => 0.0, pet => 0.0}
      assert result.unit.health == mob.unit.health
      assert result.internal.combat_zone == %State{next_at: 4_000}
      refs = for %Effects.ThreatRefGained{target_guid: guid} <- result.internal.events, do: guid
      assert Enum.sort(refs) == Enum.sort([1, 2, pet])
    end

    test "excludes dead friendly untargetable and foreign-world participants", %{mob: mob} do
      context =
        context(mob, [
          {1, 3.0, %{alive?: false}},
          {2, 4.0, %{unit_flags: 2}},
          {3, 5.0, %{faction_template: enemy_faction()}},
          {4, 6.0, %{}},
          {5, 7.0, %{}}
        ])

      context = put_in(context.perception.entities[4].position, {WorldRef.instance(36, 2), 6.0, 0.0, 0.0})
      result = ZoneCombat.pulse(mob, true, context)
      assert result.unit.target == 5
      assert Threat.targets(result) == [5]
    end

    test "later pulses skip players already in combat and preserve the current victim and threat", %{mob: mob} do
      context = context(mob, [{1, 10.0, %{}}])
      fighting = mob |> ZoneCombat.pulse(true, context) |> Threat.add(1, 25)
      pet = Guid.from_low_guid(:pet, 1, 8)
      context = context(mob, [{1, 10.0, %{in_combat: true}}, {2, 2.0, %{}}, {pet, 4.0, %{owner_guid: 1}}], %{1 => pet})
      result = ZoneCombat.pulse(fighting, false, context)
      assert result.unit.target == 1
      assert result.internal.threat == %{1 => 25.0, 2 => 0.0}
      refute Map.has_key?(result.internal.threat, pet)
    end

    test "passive creatures retain their reaction and existing engagements", %{mob: mob} do
      passive = put_in(mob.internal.creature.reaction_state, :passive)
      context = context(passive, [{1, 10.0, %{}}, {2, 20.0, %{}}])
      idle = ZoneCombat.pulse(passive, true, context)
      refute idle.internal.in_combat
      assert Threat.targets(idle) == []
      assert idle.unit.target in [nil, 0]

      fighting = Engagement.enter(passive, 1, 0, selection: :target, allow_passive?: true).entity
      result = ZoneCombat.pulse(fighting, true, context)
      assert result.unit.target == 1
      assert Threat.targets(result) == [1, 2]
    end

    test "requires a living threat-list owner and a dungeon snapshot", %{mob: mob} do
      context = context(mob, [{1, 10.0, %{}}])

      variants = [
        put_in(mob.unit.health, 0),
        put_in(mob.unit.charmed_by, 1),
        put_in(mob.internal.pet, %Pet{owner_guid: 1, kind: :guardian}),
        put_in(mob.internal.totem, %Totem{}),
        put_in(mob.internal.creature.extra_flags, 0x800)
      ]

      for source <- variants, do: assert(ZoneCombat.pulse(source, true, context) == source)
      assert ZoneCombat.pulse(mob, true, %{context | combat_zone: nil}) == mob
      assert ZoneCombat.pulse(mob, true, context(mob, [])) == mob
      foreign = put_in(context.combat_zone.world, WorldRef.instance(36, 2))
      assert ZoneCombat.pulse(mob, true, foreign) == mob
      npc_pet = put_in(mob.internal.pet, %Pet{owner_guid: Guid.from_low_guid(:mob, 1, 1), kind: :creature_pet})
      assert ZoneCombat.eligible?(npc_pet)
    end

    test "runs aggro events once even when their action requests another pulse", %{mob: mob} do
      steps = [%ScriptStep{command: :zone_combat_pulse, datalong: 1}, %ScriptStep{command: :set_phase, datalong: 7}]
      event = %AIEvent{id: 1, event_type: :aggro, actions: [steps]}
      mob = put_in(mob.internal.creature.ai_events, [event])
      result = ZoneCombat.pulse(mob, true, context(mob, [{1, 10.0, %{}}, {2, 20.0, %{}}]))
      assert result.internal.blackboard.event_ai.phase == 7
      assert Threat.targets(result) == [1, 2]
      assert Enum.count(result.internal.events, &is_struct(&1, Effects.ThreatRefGained)) == 2
    end
  end

  describe "maintain/2" do
    test "automatic activation follows the initial player or player-owned pet contact", %{mob: mob} do
      mob = put_in(mob.internal.creature.static_flags2, 2)
      pet = Guid.from_low_guid(:pet, 1, 9)
      context = context(mob, [{1, 10.0, %{}}, {2, 20.0, %{}}, {pet, 5.0, %{owner_guid: 1}}])

      for source <- [1, pet] do
        fighting = Engagement.enter(mob, source, 1_000, selection: :target).entity
        assert fighting.internal.combat_zone == %State{source_guid: source}

        assert %TickPlan.Wake{source: :zone_combat, at: 1_000} =
                 Tick.plan(fighting, {:running, 5_000}, 1_000) |> TickPlan.next()

        pulsed = ZoneCombat.maintain(fighting, context)
        assert pulsed.unit.target == source
        assert Enum.all?([1, 2], &(&1 in Threat.targets(pulsed)))
        assert pulsed.internal.combat_zone == %State{next_at: 4_000}
      end
    end

    test "NPC contact does not activate the flag", %{mob: mob} do
      mob = put_in(mob.internal.creature.static_flags2, 2)
      npc = Guid.from_low_guid(:mob, 1, 4)
      fighting = Engagement.enter(mob, npc, 1_000, selection: :target).entity
      result = ZoneCombat.maintain(fighting, context(mob, [{1, 10.0, %{}}, {npc, 3.0, %{}}]))
      assert result.internal.combat_zone == nil
      assert Threat.targets(result) == [npc]
    end

    test "schedules three-second pulses and advances an empty snapshot without spinning", %{mob: mob} do
      context = context(mob, [{1, 10.0, %{}}])
      fighting = ZoneCombat.pulse(mob, true, context)
      later = context(mob, [{1, 10.0, %{in_combat: true}}, {2, 20.0, %{}}])
      refute ZoneCombat.observe?(fighting, 3_999)
      assert ZoneCombat.observe?(fighting, 4_000)
      assert ZoneCombat.maintain(fighting, %{later | now: 3_999}) == fighting
      result = ZoneCombat.maintain(fighting, %{later | now: 4_000})
      assert Threat.targets(result) == [1, 2]
      assert result.internal.combat_zone.next_at == 7_000
      result = ZoneCombat.maintain(result, %{context(mob, []) | now: 7_000})
      assert result.internal.combat_zone.next_at == 10_000
    end

    test "a hard leash blocks further recruitment until the creature resets", %{mob: mob} do
      mob = put_in(mob.internal.creature.leash_range, 20.0)
      fighting = ZoneCombat.pulse(mob, true, context(mob, [{1, 10.0, %{}}]))
      fighting = put_in(fighting.movement_block.position, {30.0, 0.0, 0.0, 0.0})
      context = %{context(mob, [{1, 10.0, %{in_combat: true}}, {2, 40.0, %{}}]) | now: 4_000}
      result = ZoneCombat.maintain(fighting, context)
      assert Threat.targets(result) == [1]
      assert result.internal.combat_zone.next_at == 7_000
    end

    test "combat exit clears the pulse while stopping only the attack preserves it", %{mob: mob} do
      context = context(mob, [{1, 10.0, %{}}])
      fighting = ZoneCombat.pulse(mob, true, context)
      assert Engagement.stop_attack(fighting).entity.internal.combat_zone == fighting.internal.combat_zone

      for reason <- [:evade, :death, :reset, :combat_stop] do
        stopped = Engagement.leave(fighting, reason, 1_000).entity
        assert stopped.internal.combat_zone == nil
        assert ZoneCombat.maintain(stopped, %{context | now: 100_000}) == stopped
        assert ZoneCombat.next_at(stopped, 100_000) == nil
      end
    end
  end

  describe "Script.execute_steps/5" do
    test "requests dungeon observations for nested scripts and preserves blackboard changes", %{mob: mob} do
      pulse = %ScriptStep{command: :zone_combat_pulse, datalong: 1}
      nested = %ScriptStep{command: :start_script, sub_scripts: %{1 => [pulse]}}
      assert Request.for_script([nested], [1]).combat_zone?
      steps = [%ScriptStep{command: :set_phase, datalong: 4}, pulse]
      {result, memory} = Script.execute_steps(mob, Blackboard.new(), steps, 1, context(mob, [{1, 10.0, %{}}]))
      assert result.unit.target == 1
      assert memory.event_ai.phase == 4
    end

    test "dead and non-creature sources honor abort", %{mob: mob} do
      for source <- [put_in(mob.unit.health, 0), %Character{object: %Object{guid: 1}, internal: %Internal{}}],
          abort? <- [true, false] do
        steps = [
          %ScriptStep{command: :zone_combat_pulse, datalong: 1, abort_on_failure?: abort?},
          %ScriptStep{command: :set_phase, datalong: 4}
        ]

        {_, memory} = Script.execute_steps(source, Blackboard.new(), steps, 1, Context.new(1_000))
        assert memory.event_ai.phase == if(abort?, do: 0, else: 4)
      end
    end

    @tag :vmangos_db
    test "loads General Rajaxx's initial combat pulse" do
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [1_534_101])
      assert Enum.any?(scripts[1_534_101], &match?(%ScriptStep{command: :zone_combat_pulse, datalong: 1}, &1))
    end
  end

  defp creature(_context) do
    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1), entry: 1},
      unit: %Unit{health: 100, max_health: 100, level: 20, flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(36, 1),
        in_combat: false,
        creature: %Creature{},
        blackboard: Blackboard.new()
      }
    }

    %{mob: mob}
  end

  defp context(mob, actors, pets \\ %{}) do
    source = %Observation{guid: mob.object.guid, metadata: %{alive?: true, faction_template: enemy_faction()}}

    observations =
      Map.new(actors, fn {guid, distance, overrides} ->
        metadata =
          Map.merge(%{alive?: true, in_combat: false, faction_template: player_faction(), unit_flags: 0}, overrides)

        {guid,
         %Observation{
           guid: guid,
           distance: distance,
           position: {mob.internal.world, distance, 0.0, 0.0},
           metadata: metadata
         }}
      end)
      |> Map.put(mob.object.guid, source)

    players = for {guid, _, _} <- actors, Guid.entity_type(guid) == :player, do: guid
    zone = %CombatZone{world: mob.internal.world, players: players, pets: pets}
    perception = Perception.new(1_000, {mob.internal.world, 0.0, 0.0, 0.0}, observations, %{})
    Context.new(1_000, perception: perception, combat_zone: zone)
  end

  defp enemy_faction, do: %FactionTemplate{id: 17, faction: 15, faction_group: 8, friend_group: 8, enemy_group: 1}
  defp player_faction, do: %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
end
