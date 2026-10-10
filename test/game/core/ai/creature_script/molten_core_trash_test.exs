defmodule ThistleTea.Game.Core.AI.CreatureScript.MoltenCoreTrashTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.Script.Run
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:combatants]

  describe "Firewalker" do
    test "fires six timed blossoms and selects against the current threat list", %{players: [first, second]} do
      mob = creature(11_666, [first, second])
      {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), first, 0, context(mob, 0))
      {early, _} = EventAI.tick(clear_effects(mob), blackboard, 5_999, context(mob, 5_999))
      refute Enum.any?(early.internal.events, &is_struct(&1, Effects.SpellStart))
      {mob, blackboard} = EventAI.tick(clear_effects(mob), blackboard, 6_000, context(mob, 6_000))
      assert spell_starts(mob) == [{19_636, mob.object.guid}]
      assert [%Effects.ScriptSteps{duration_ms: 1_000} = timer] = timers(mob)

      {mob, blackboard} = resume(mob, blackboard, timer, 7_000)
      assert spell_starts(mob) == [{19_637, first}]
      mob = %{mob | internal: %{mob.internal | threat: %{second => 1}}}

      {mob, _blackboard} =
        Enum.reduce(8_000..12_000//1_000, {mob, blackboard}, fn now, {mob, blackboard} ->
          [timer] = timers(mob)
          {mob, blackboard} = resume(mob, blackboard, timer, now)
          assert spell_starts(mob) == [{19_637, second}]
          {mob, blackboard}
        end)

      assert mob.internal.scripts.runs == %{}
      assert timers(mob) == []
    end

    test "evade and death cancel the remaining burst receipts", %{players: [first | _] = players} do
      for ending <- [:evade, :death] do
        mob = creature(11_666, players)
        {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), first, 0, context(mob, 0))
        {mob, blackboard} = EventAI.tick(clear_effects(mob), blackboard, 6_000, context(mob, 6_000))
        [timer] = timers(mob)

        {mob, blackboard} =
          case ending do
            :evade -> EventAI.on_evade(clear_effects(mob), blackboard, 6_500, context(mob, 6_500))
            :death -> EventAI.on_death(clear_effects(mob), blackboard, first, 6_500, context(mob, 6_500))
          end

        assert mob.internal.scripts.runs == %{}
        {mob, _blackboard} = resume(mob, blackboard, timer, 7_000)
        assert spell_starts(mob) == []
      end
    end
  end

  describe "Firelord" do
    test "uses Incinerate, player-only Soul Burn and repeating Lava Spawn casts", %{players: [first | _] = players} do
      mob = creature(11_668, players)
      npc = Guid.from_low_guid(:mob, 11_666, Unique.integer())
      mob = %{mob | internal: %{mob.internal | threat: Map.put(mob.internal.threat, npc, 100)}}
      {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), first, 0, context(mob, 0))
      assert Enum.any?(mob.internal.events, &match?(%Effects.TriggerSpell{spell_id: 19_396}, &1))
      {mob, blackboard} = EventAI.tick(clear_effects(mob), blackboard, 4_000, context(mob, 4_000))

      assert [%Effects.TriggerSpell{spell_id: 19_393, target_guid: ^first}] =
               Enum.filter(mob.internal.events, &is_struct(&1, Effects.TriggerSpell))

      {mob, blackboard} = EventAI.tick(clear_effects(mob), blackboard, 7_500, context(mob, 7_500))
      assert spell_starts(mob) == [{19_569, mob.object.guid}]
      {early, _} = EventAI.tick(clear_effects(mob), blackboard, 22_499, context(mob, 22_499))
      assert spell_starts(early) == []
      {mob, _blackboard} = EventAI.tick(clear_effects(mob), blackboard, 22_500, context(mob, 22_500))
      assert spell_starts(mob) == [{19_569, mob.object.guid}]
    end

    test "forwards each new spawn to attack its summoner's opponents", %{players: [first | _] = players} do
      parent = creature(11_668, players)
      child = creature(12_265, [])
      child = %{child | internal: %{child.internal | spawn: %Spawn{summoner_guid: parent.object.guid}}}

      event = %SummonEvent{
        event: :summoned_unit,
        entry: 12_265,
        world: parent.internal.world,
        observation: %Observation{guid: child.object.guid}
      }

      {parent, _blackboard} = EventAI.on_summon_event(parent, Blackboard.new(), event, context(parent, 0))

      assert [%Effects.ForwardScriptSteps{target_guid: summon, steps: [step]}] =
               Enum.filter(parent.internal.events, &is_struct(&1, Effects.ForwardScriptSteps))

      assert summon == child.object.guid
      child_context = context(child, 0, %{parent.object.guid => %{combat_targets: players}})
      {child, _blackboard} = Script.run(child, Blackboard.new(), [step], parent.object.guid, child_context)
      assert [%Effects.StartAttack{target_guid: ^first}] = child.internal.events
    end
  end

  defp combatants(_context), do: %{players: [Unique.integer(), Unique.integer()]}

  defp creature(entry, players) do
    spells = Map.new([19_635, 19_636, 19_637, 19_569], &{&1, %Spell{id: &1, cast_time_ms: 0, effects: []}})

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, level: 60, target: List.first(players), auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(409, Unique.integer()),
        in_combat: players != [],
        creature: %Creature{ai_events: CreatureScript.events(entry)},
        threat: Map.new(players, &{&1, 1}),
        spellbook: spells,
        blackboard: Blackboard.new()
      }
    }
  end

  defp context(mob, now, extra \\ %{}) do
    entities =
      Map.new([mob.object.guid | Map.keys(mob.internal.threat)], fn guid ->
        {guid, %Observation{guid: guid, position: {mob.internal.world, 0.0, 0.0, 0.0}, metadata: %{alive?: true}}}
      end)

    entities =
      Map.merge(
        entities,
        Map.new(extra, fn {guid, metadata} -> {guid, %Observation{guid: guid, metadata: metadata}} end)
      )

    perception = Perception.new(now, {mob.internal.world, 0.0, 0.0, 0.0}, entities, %{})
    Context.new(now, perception: perception, random: Random.fixed())
  end

  defp resume(mob, blackboard, timer, now) do
    Run.resume(
      clear_effects(mob),
      blackboard,
      timer.run_id,
      timer.receipt,
      mob.internal.world,
      :continue,
      context(mob, now)
    )
  end

  defp clear_effects(mob), do: %{mob | internal: %{mob.internal | events: []}}
  defp timers(mob), do: Enum.filter(mob.internal.events, &is_struct(&1, Effects.ScriptSteps))

  defp spell_starts(mob) do
    for %Effects.SpellStart{spell_id: spell, targets: targets} <- mob.internal.events,
        do: {spell, Target.unit_guid(targets)}
  end
end
