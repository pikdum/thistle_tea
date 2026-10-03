defmodule ThistleTea.Game.Core.AI.CreatureScript.WesternPlaguelandsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @cauldron 11_152
  @felstone_cauldron 45_420
  @dalsons_cauldron 45_421
  @bilemaw 11_075
  @malvinious 11_077
  @tower_one 10_902

  describe "the Scourge Cauldron" do
    test "calls up its own field's lord for a player on that field's quest" do
      player = Guid.from_low_guid(:player, Unique.integer())
      felstone = mob(@cauldron, @felstone_cauldron)

      {fired, _blackboard} = EventAI.tick(felstone, Blackboard.new(), 1_000, sighting(felstone, player, 5_216))

      assert [%Effects.SummonCreature{summon: %{entry: @bilemaw, despawn_delay_ms: 600_000}}, despawn] =
               fired.internal.events

      assert despawn == Effects.despawn_self(0, 600_000)

      dalsons = mob(@cauldron, @dalsons_cauldron)
      {ignored, _blackboard} = EventAI.tick(dalsons, Blackboard.new(), 1_000, sighting(dalsons, player, 5_216))
      assert ignored.internal.events == []

      {fired, _blackboard} = EventAI.tick(dalsons, Blackboard.new(), 1_000, sighting(dalsons, player, 5_231))
      assert [%Effects.SummonCreature{summon: %{entry: @malvinious}}, _despawn] = fired.internal.events
    end

    test "stays quiet for players without the quest" do
      player = Guid.from_low_guid(:player, Unique.integer())
      felstone = mob(@cauldron, @felstone_cauldron)

      {ignored, _blackboard} = EventAI.tick(felstone, Blackboard.new(), 1_000, sighting(felstone, player, 5_097))
      assert ignored.internal.events == []
    end
  end

  describe "the Andorhal watchtowers" do
    test "credit a player on the quest while a beacon torch burns nearby" do
      player = Guid.from_low_guid(:player, Unique.integer())
      tower = mob(@tower_one, nil)
      [%{condition: %Condition{children: [torch, _quests]}}] = CreatureScript.events(@tower_one)

      lit = sighting(tower, player, 5_097, %{player => %{torch => :met}})
      {credited, _blackboard} = EventAI.tick(tower, Blackboard.new(), 1_000, lit)

      assert [%Effects.QuestKillCredit{player_guid: ^player, creature_entry: @tower_one}] = credited.internal.events

      dark = sighting(tower, player, 5_097, %{player => %{torch => :unmet}})
      {ignored, _blackboard} = EventAI.tick(tower, Blackboard.new(), 1_000, dark)
      assert ignored.internal.events == []
    end
  end

  defp sighting(mob, player, quest_id, condition_results \\ %{}) do
    source = mob.object.guid
    quest_log = %{0 => %QuestLog.Entry{quest_id: quest_id, status: :incomplete}}
    subject = %Subject{guid: player, kind: :player, quest_log: quest_log}

    observations = %{
      source => %Observation{guid: source, metadata: %{}},
      player => %Observation{guid: player, metadata: %{condition_subject: subject}, distance: 25.0}
    }

    nearby = %{mobs: [], players: [{player, 25.0}], game_objects: []}

    Context.new(1_000,
      perception: Perception.new(1_000, nil, observations, nearby),
      script_conditions_by_target: condition_results
    )
  end

  defp mob(entry, db_guid) do
    EventAI.specialize(%Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "The Scourge Cauldron",
        creature: %Creature{ai_events: CreatureScript.events(entry), db_guid: db_guid}
      }
    })
  end
end
