defmodule ThistleTea.Game.Core.AI.AreaTriggerScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest.QuestLog.Entry
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @position {100.0, 200.0, 300.0}
  @warrior 1
  @hunter 3
  @ancients [14_524, 14_525, 14_526]

  describe "steps/2" do
    test "leaves unported triggers to their database scripts" do
      refute AreaTriggerScript.ported?(1125)
      assert AreaTriggerScript.steps(1125, @position) == nil
    end

    test "Ravenholdt's courtyard credits a rogue still looking for the manor" do
      player = character(quests: [{6681, :incomplete}])
      guid = player.object.guid

      assert [%Effects.QuestKillCredit{player_guid: ^guid, creature_entry: 13_936}] = effects(3066, player)
      assert [] = effects(3066, character(quests: [{6681, :complete}]))
      assert [] = effects(3066, character())
    end

    test "Lar'korwi's mate answers the scent where the player stepped in" do
      assert [%Effects.SummonCreature{summon: summon}] = effects(1731, character(quests: [{4291, :incomplete}]))

      assert %{
               entry: 9683,
               position: {100.0, 200.0, 300.0, 3.3},
               unique?: true,
               unique_distance: 25,
               despawn_type: 1,
               despawn_delay_ms: 120_000,
               attack_guid: nil
             } = summon

      assert [] = effects(1766, character())
    end

    test "the ancients wake for a hunter partway through their chain" do
      for hunter <- [
            character(class: @hunter, quests: [{7632, :complete}]),
            character(class: @hunter, rewarded: [7632])
          ] do
        summons = effects(3587, hunter)

        assert Enum.map(summons, & &1.summon.entry) == @ancients

        assert Enum.all?(
                 summons,
                 &match?(%{despawn_type: 3, despawn_delay_ms: 600_000, unique_distance: 100}, &1.summon)
               )
      end
    end

    test "the ancients stay asleep for others" do
      for player <- [
            character(class: @hunter),
            character(class: @hunter, quests: [{7632, :incomplete}]),
            character(class: @hunter, rewarded: [7632, 7636]),
            character(class: @warrior, quests: [{7632, :complete}])
          ] do
        assert [] = effects(3587, player)
      end
    end
  end

  describe "summon_entries/0" do
    test "lists every creature a trigger can call" do
      assert Enum.sort(AreaTriggerScript.summon_entries()) == [9683 | @ancients]
    end
  end

  defp effects(trigger_id, %Character{object: %Object{guid: guid}} = player) do
    steps = AreaTriggerScript.steps(trigger_id, @position)
    {player, _blackboard} = Script.run(player, Blackboard.new(), steps, guid, Context.new(0))

    Enum.filter(player.internal.events, &(&1.__struct__ in [Effects.QuestKillCredit, Effects.SummonCreature]))
  end

  defp character(opts \\ []) do
    quest_log =
      opts
      |> Keyword.get(:quests, [])
      |> Enum.with_index()
      |> Map.new(fn {{quest_id, status}, slot} -> {slot, %Entry{quest_id: quest_id, status: status}} end)

    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, Unique.integer())},
      unit: %Unit{race: 1, class: Keyword.get(opts, :class, @warrior), health: 100, max_health: 100, auras: []},
      player: %Player{quest_log: quest_log, rewarded_quests: MapSet.new(Keyword.get(opts, :rewarded, []))},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(1), spellbook: %{}}
    }
  end
end
