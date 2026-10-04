defmodule ThistleTea.Game.Core.AI.AreaTriggerScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
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

    test "a Children's Week sight counts only with the right orphan along" do
      player = character(quests: [{1479, :incomplete}], mini_pet: 14_305)
      guid = player.object.guid

      assert [%Effects.QuestEventCredit{player_guid: ^guid, quest_id: 1479}] = effects(3546, player)
      assert [] = effects(3546, character(quests: [{1479, :incomplete}], mini_pet: 14_444))
      assert [] = effects(3546, character(quests: [{1479, :incomplete}]))
      assert [%Effects.QuestEventCredit{quest_id: 910}] = effects(3550, character(mini_pet: 14_444))
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

  describe "Huldar and Miran's camp" do
    setup do
      %{saean: Guid.from_low_guid(:mob, 1380, Unique.integer())}
    end

    test "credits the delivery and turns Saean on Miran", %{saean: saean} do
      player = character(quests: [{273, :incomplete}])
      guid = player.object.guid

      assert [
               %Effects.QuestEventCredit{player_guid: ^guid, quest_id: 273},
               %Effects.ForwardScriptSteps{target_guid: ^saean, source_guid: ^guid, steps: [saean_turns]}
             ] = effects(171, player, ambush_context(saean, :met))

      assert %ScriptStep{command: :start_script, condition: nil} = saean_turns

      assert [
               %ScriptStep{command: :set_faction, datalong: 54, datalong2: 1},
               %ScriptStep{command: :summon_creature, datalong: 1981, dataint3: 10, target_param1: 1379},
               %ScriptStep{command: :summon_creature, datalong: 1981, dataint3: 10, target_param1: 1379},
               %ScriptStep{command: :attack_start, target_type: :nearest_creature_with_entry, target_param1: 1379}
             ] = Map.fetch!(saean_turns.sub_scripts, saean_turns.datalong)
    end

    test "only credits the delivery when the camp is not ready", %{saean: saean} do
      player = character(quests: [{273, :incomplete}])

      assert [%Effects.QuestEventCredit{quest_id: 273}] = effects(171, player, ambush_context(saean, :unmet))
    end

    test "leaves the camp alone for players without the delivery", %{saean: saean} do
      assert [] = effects(171, character(quests: [{273, :complete}]), ambush_context(saean, :unmet))
    end
  end

  describe "Sentry Point" do
    test "credits the report and brings Tervosh in from Theramore" do
      player = character(quests: [{1265, :incomplete}])
      guid = player.object.guid

      assert [
               %Effects.SummonCreature{summon: summon, steps: visit, target_guid: ^guid},
               %Effects.QuestEventCredit{player_guid: ^guid, quest_id: 1265}
             ] = effects(1667, player)

      assert %{entry: 4967, despawn_type: 3, despawn_delay_ms: 63_000, unique?: true, attack_guid: nil} = summon

      assert [
               %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x280, datalong3: 1},
               %ScriptStep{command: :cast_spell, datalong: 7141, delay_ms: 1_000},
               %ScriptStep{command: :emote, datalong: 66, target_param1: 5085, swap_final?: true},
               %ScriptStep{command: :cast_spell, datalong: 7077, delay_ms: 61_000}
             ] = visit

      assert [] = effects(1667, character())
    end

    test "answers the tower entrance the door reports" do
      assert AreaTriggerScript.steps(302, @position) == AreaTriggerScript.steps(1667, @position)
    end
  end

  describe "the Affray ring" do
    test "calls Twiggy to start the fight for a player on The Affray" do
      player = character(quests: [{1719, :incomplete}])
      guid = player.object.guid
      twiggy = Guid.from_low_guid(:mob, 6248, Unique.integer())
      perception = Perception.new(0, nil, %{}, %{mobs: [{twiggy, 12.0}], players: [], game_objects: []})

      assert [
               %Effects.ForwardScriptSteps{
                 target_guid: ^twiggy,
                 source_guid: ^guid,
                 steps: [%ScriptStep{command: :send_script_event, datalong: 1}]
               }
             ] = effects(522, player, Context.new(0, perception: perception))

      assert [] = effects(522, character(quests: [{1719, :complete}]), Context.new(0, perception: perception))
    end
  end

  describe "the Twilight Grove" do
    test "the nearest Twilight Corrupter whispers to a player on The Nightmare's Corruption" do
      player = character(quests: [{8735, :incomplete}])
      guid = player.object.guid
      corrupter = Guid.from_low_guid(:mob, 15_625, Unique.integer())
      perception = Perception.new(0, nil, %{}, %{mobs: [{corrupter, 300.0}], players: [], game_objects: []})

      assert [
               %Effects.ForwardScriptSteps{
                 target_guid: ^corrupter,
                 source_guid: ^guid,
                 steps: [%ScriptStep{command: :talk, datalong: 4, dataint: 11_271}]
               }
             ] = effects(4017, player, Context.new(0, perception: perception))
    end

    test "raises a Twilight Corrupter to whisper when none is about" do
      player = character(quests: [{8735, :incomplete}])
      guid = player.object.guid

      assert [%Effects.SummonCreature{summon: summon, steps: arrival, target_guid: ^guid}] = effects(4017, player)

      assert %{
               entry: 15_625,
               position: {-10_335.9, -489.051, 50.6233, 2.59373},
               despawn_type: 7,
               unique?: true,
               unique_limit: 1,
               unique_distance: 350,
               attack_guid: nil
             } = summon

      assert [%ScriptStep{command: :talk, datalong: 4, dataint: 11_271, target_type: :provided}] = arrival
    end

    test "leaves the grove quiet for everyone else" do
      assert [] = effects(4017, character())
      assert [] = effects(4017, character(quests: [{8735, :complete}]))
    end
  end

  describe "the Greymist camp" do
    test "calls a hidden Murkdeep out for a player on WANTED: Murkdeep!" do
      player = character(quests: [{4740, :incomplete}])
      guid = player.object.guid

      assert [%Effects.SummonCreature{summon: summon, steps: event, target_guid: ^guid}] = effects(1966, player)

      assert %{
               entry: 10_323,
               despawn_type: 1,
               despawn_delay_ms: 1_800_000,
               unique?: true,
               unique_limit: 1,
               unique_distance: 100,
               attack_guid: nil
             } = summon

      assert [
               %ScriptStep{command: :morph, datalong: 11_686, datalong2: 1, delay_ms: 0},
               %ScriptStep{command: :modify_flags, datalong: 46, datalong3: 1},
               %ScriptStep{command: :set_react_state, datalong: 0} | waves
             ] = event

      summons = Enum.filter(waves, &(&1.command == :summon_creature))

      assert Enum.map(summons, &{&1.delay_ms, &1.datalong}) == [
               {1_000, 2_202},
               {1_000, 2_202},
               {1_000, 2_202},
               {31_000, 2_205},
               {31_000, 2_205},
               {61_000, 2_206}
             ]

      assert Enum.all?(summons, &match?(%ScriptStep{dataint3: 0, dataint4: 1, datalong2: 600_000}, &1))

      assert [%ScriptStep{delay_ms: 61_000}] = Enum.filter(waves, &(&1.command == :attack_start))

      assert waves |> Enum.filter(&(&1.command == :despawn)) |> Enum.map(&{&1.delay_ms, &1.condition.reverse?}) ==
               [{1_000, true}, {31_000, true}, {61_000, true}]
    end

    test "leaves the camp quiet for everyone else" do
      assert [] = effects(1966, character())
      assert [] = effects(1966, character(quests: [{4740, :complete}]))
    end
  end

  describe "Zul'Farrak" do
    test "Zum'rah turns on intruders once per copy while he is near" do
      [%ScriptStep{command: :start_script, condition: condition, sub_scripts: %{1 => [mark, wake]}}] =
        AreaTriggerScript.steps(962, @position)

      assert %Condition{
               type: :and,
               children: [
                 %Condition{type: :instance_data, value1: 4, value2: 0, value3: 0},
                 %Condition{type: :nearby_creature, value1: 7_271, value2: 30}
               ]
             } = condition

      assert %ScriptStep{command: :set_instance_data, datalong: 4, datalong2: 1} = mark

      assert %ScriptStep{command: :start_script, target_param1: 7_271, swap_final?: true, sub_scripts: %{1 => zumrah}} =
               wake

      assert [
               %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x100, datalong3: 2},
               %ScriptStep{command: :set_faction, datalong: 37},
               %ScriptStep{command: :talk, dataint: 3_622}
             ] = zumrah
    end

    test "Antu'sul hatches four broodlings on the dungeon and comes down to the basin" do
      [%ScriptStep{sub_scripts: %{1 => [mark, wake]}}] = AreaTriggerScript.steps(1447, @position)
      assert %ScriptStep{command: :set_instance_data, datalong: 5, datalong2: 1} = mark
      assert %ScriptStep{target_param1: 8_127, target_param2: 100, sub_scripts: %{1 => [lunch | rest]}} = wake
      {broodlings, [descend]} = Enum.split(rest, -1)

      assert %ScriptStep{command: :talk, dataint: 4_166} = lunch
      assert length(broodlings) == 4

      for broodling <- broodlings do
        assert %ScriptStep{command: :summon_creature, datalong: 8_138, datalong2: 25_000, dataint4: 1} = broodling
        assert %{1 => [%ScriptStep{command: :zone_combat_pulse, datalong: 1}]} = broodling.sub_scripts
      end

      assert %ScriptStep{command: :move_to, datalong3: 5, position: {1_805.133667, 740.349304, _, _}} = descend
    end
  end

  describe "Blackrock Depths" do
    test "stepping into the Ring of Law asks the instance to start the fight" do
      assert [%ScriptStep{command: :set_instance_data, datalong: 0, datalong2: 1, condition: nil}] =
               AreaTriggerScript.steps(1526, @position)
    end
  end

  describe "Blackrock Spire" do
    test "the Dragonspine Door opens for a player carrying the Seal of Ascension" do
      player = %{character() | internal: %{character().internal | world: WorldRef.instance(229, 1)}}
      guid = player.object.guid
      steps = AreaTriggerScript.steps(2046, @position)

      sealed = %Condition.Subject{guid: guid, kind: :player, item_counts: %{12_344 => 1}}
      empty = %{sealed | item_counts: %{12_344 => 0}}

      for {published, fields} <- [{sealed, [5]}, {empty, []}] do
        observation = %Observation{guid: guid, metadata: %{condition_subject: published}}
        context = Context.new(0, perception: Perception.new(0, nil, %{guid => observation}, %{}))
        {player, _blackboard} = Script.run(player, Blackboard.new(), steps, guid, context)

        commands = for %Effects.InstanceDataCommand{field: field, value: 3} <- player.internal.events, do: field
        assert commands == fields
      end
    end

    test "The Beast leaves its furnace for anyone stepping in while it is idle" do
      assert [
               %ScriptStep{
                 command: :attack_start,
                 target_param1: 10_430,
                 swap_final?: true,
                 condition: %Condition{type: :in_combat, reverse?: true, swap_targets?: true}
               }
             ] = AreaTriggerScript.steps(2066, @position)
    end
  end

  describe "summon_entries/0" do
    test "lists every creature a trigger can call" do
      assert Enum.sort(AreaTriggerScript.summon_entries()) ==
               Enum.sort([1981, 2202, 2205, 2206, 4967, 8138, 9683, 10_323, 15_625 | @ancients])
    end
  end

  defp ambush_context(saean, ready) do
    [_credit, ambush] = AreaTriggerScript.steps(171, @position)
    perception = Perception.new(0, nil, %{}, %{mobs: [{saean, 20.0}], players: [], game_objects: []})
    Context.new(0, perception: perception, script_conditions: %{ambush.condition => ready})
  end

  defp effects(trigger_id, %Character{object: %Object{guid: guid}} = player, context \\ Context.new(0)) do
    steps = AreaTriggerScript.steps(trigger_id, @position)
    {player, _blackboard} = Script.run(player, Blackboard.new(), steps, guid, context)

    Enum.filter(
      player.internal.events,
      &(&1.__struct__ in [
          Effects.QuestKillCredit,
          Effects.QuestEventCredit,
          Effects.SummonCreature,
          Effects.ForwardScriptSteps
        ])
    )
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
      internal: %Internal{world: WorldRef.open(1), spellbook: %{}, mini_pet: mini_pet(Keyword.get(opts, :mini_pet))}
    }
  end

  defp mini_pet(nil), do: nil

  defp mini_pet(entry),
    do: %EntityRef{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry, spell_id: 0}
end
