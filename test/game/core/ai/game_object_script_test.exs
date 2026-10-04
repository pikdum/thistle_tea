defmodule ThistleTea.Game.Core.AI.GameObjectScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
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

  @cask_position {2.79373, 432.367, 104.308, -1.6057}
  @resonite_cask 178_145
  @crystal 176_581
  @basket 179_910
  @panther_cage 176_195
  @landmark 142_189
  @treasure_hunters [7_899, 7_901, 7_902]
  @stone_position {-7_959.77, 1_824.89, 3.53474, 1.2}
  @lesser_wind_stone 180_456
  @wind_stone 180_461
  @greater_wind_stone 180_466
  @templars [15_209, 15_211, 15_212, 15_307]
  @abyssal_council @templars ++ [15_206, 15_207, 15_208, 15_220, 15_203, 15_204, 15_205, 15_305]

  describe "steps/2" do
    test "leaves unported objects to their database scripts" do
      refute GameObjectScript.ported?(1_234)
      assert GameObjectScript.steps(1_234, @cask_position) == []
    end

    test "the Resonite Cask raises Goggeroc beside it" do
      assert [%Effects.SummonCreature{summon: summon}] = effects(@resonite_cask, character())

      assert %{entry: 11_920, despawn_type: 4, despawn_delay_ms: 300_000, attack_guid: nil, position: {x, y, z, _o}} =
               summon

      assert_in_delta :math.sqrt((x - 2.79373) ** 2 + (y - 432.367) ** 2), 0.5, 0.001
      assert z == 104.308
    end

    test "the Hand of Iruxos crystal calls one Demon Spirit to attack whoever touched it" do
      player = character()
      guid = player.object.guid

      assert [%Effects.SummonCreature{summon: summon}] = effects(@crystal, player)

      assert %{
               entry: 11_876,
               despawn_type: 4,
               despawn_delay_ms: 15_000,
               unique?: true,
               unique_limit: 1,
               attack_guid: ^guid,
               position: {-346.84, 1_765.13, 138.39, 5.91}
             } = summon
    end

    test "Lard's Picnic Basket springs three kidnappers on the player while none are about" do
      player = character()
      guid = player.object.guid
      [ambush] = GameObjectScript.steps(@basket, @cask_position)

      quiet = Context.new(0, script_conditions: %{ambush.condition => true})
      summons = effects(@basket, player, quiet)

      assert length(summons) == 3

      assert Enum.all?(
               summons,
               &match?(
                 %Effects.SummonCreature{
                   summon: %{entry: 14_748, despawn_type: 1, despawn_delay_ms: 30_000, attack_guid: ^guid}
                 },
                 &1
               )
             )

      assert [] = effects(@basket, player, Context.new(0, script_conditions: %{ambush.condition => false}))
    end

    test "the Panther Cage sets the Enraged Panther on a player after the Hypercapacitor Gizmo" do
      player = character(quests: [{5151, :incomplete}])
      guid = player.object.guid
      panther = Guid.from_low_guid(:mob, 10_992, Unique.integer())
      perception = Perception.new(0, nil, %{}, %{mobs: [{panther, 3.0}], players: [], game_objects: []})
      context = Context.new(0, perception: perception)

      assert [%Effects.ForwardScriptSteps{target_guid: ^panther, source_guid: ^guid, steps: [release]}] =
               effects(@panther_cage, player, context)

      assert %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x102, datalong3: 2} = release

      assert [%ScriptStep{sub_scripts: %{1 => [_release, attack]}}] =
               GameObjectScript.steps(@panther_cage, @cask_position)

      assert %ScriptStep{command: :attack_start, swap_final?: true, target_param1: 10_992} = attack

      assert [] = effects(@panther_cage, character(quests: [{5151, :complete}]), context)
      assert [] = effects(@panther_cage, character(), context)
    end

    test "the sprite darter cage frees the pen for a player on Freedom for All Creatures" do
      steps = GameObjectScript.steps(143_979, @cask_position)

      for {quests, freed} <- [{[{2969, :incomplete}], 1}, {[{2969, :complete}], 0}, {[], 0}] do
        player = character(quests: quests)
        {player, _blackboard} = Script.run(player, Blackboard.new(), steps, player.object.guid, Context.new(0))
        commands = Enum.filter(player.internal.events, &match?(%Effects.ScriptedEventCommand{}, &1))
        assert length(commands) == freed
      end

      assert [%ScriptStep{command: :start_script_for_all, datalong2: 2, datalong3: 7_997} = free] = steps
      assert %{1 => escape} = free.sub_scripts

      assert [%ScriptStep{command: :set_faction, datalong: 10}, %ScriptStep{command: :set_run, datalong: 1} | _pick] =
               escape
    end

    test "the Tablet of Theka teaches the spider god's name on The Spider God" do
      for {quests, credited} <- [{[{2936, :incomplete}], 1}, {[{2936, :complete}], 0}, {[], 0}] do
        player = character(quests: quests)
        tablet = Guid.from_low_guid(:game_object, 142_715, Unique.integer())
        steps = GameObjectScript.steps(142_715, @cask_position)
        {player, _blackboard} = Script.run(player, Blackboard.new(), steps, tablet, Context.new(0))
        credits = Enum.filter(player.internal.events, &match?(%Effects.QuestEventCredit{quest_id: 2_936}, &1))
        assert length(credits) == credited
      end
    end

    test "the Inconspicuous Landmark brings five treasure hunters down on the player" do
      player = character()
      guid = player.object.guid

      for {roll, straggler} <- Enum.zip([1, 50, 100], @treasure_hunters) do
        context = Context.new(0, random: Random.fixed(0.5, roll))
        summons = effects(@landmark, player, context)

        assert length(summons) == 5
        assert Enum.take(summons, 3) |> Enum.map(& &1.summon.entry) == @treasure_hunters

        assert Enum.all?(
                 summons,
                 &match?(
                   %Effects.SummonCreature{
                     summon: %{despawn_type: 1, despawn_delay_ms: 310_000, attack_guid: ^guid, position: {_, _, _, _}}
                   },
                   &1
                 )
               )

        assert summons |> Enum.drop(3) |> Enum.map(& &1.summon.entry) == [straggler, straggler]
      end
    end
  end

  describe "activated/3" do
    test "leaves spells no script claims to the object action" do
      assert GameObjectScript.activated(1_234, 24_734, @stone_position) == :pass
      assert GameObjectScript.activated(@lesser_wind_stone, 12_345, @stone_position) == :pass
      assert GameObjectScript.activated(@resonite_cask, 24_734, @stone_position) == :pass
    end

    test "a lesser wind stone calls a random templar in its place and vanishes" do
      player = character()
      guid = player.object.guid
      assert {:claim, steps, 15} = GameObjectScript.activated(@lesser_wind_stone, 24_734, @stone_position)

      for {roll, templar} <- Enum.zip([1, 26, 51, 76], @templars) do
        context = Context.new(0, random: Random.fixed(0.5, roll))

        assert [
                 %Effects.SummonCreature{
                   summon: %{entry: ^templar, despawn_type: 1, despawn_delay_ms: 60_000, attack_guid: nil},
                   target_guid: ^guid
                 } = summon
               ] = run_on(player, steps, context)

        assert summon.summon.position == @stone_position
      end
    end

    test "a crest, signet, or scepter calls the lord of its element" do
      player = character()

      for {stone, spell_id, lord, position} <- [
            {@lesser_wind_stone, 24_744, 15_209, @stone_position},
            {@wind_stone, 24_765, 15_206, {-7_927.48, 1_935.30, 5.61, 4.76475}},
            {@greater_wind_stone, 24_790, 15_305, @stone_position}
          ] do
        assert {:claim, steps, 15} = GameObjectScript.activated(stone, spell_id, @stone_position)

        assert [%Effects.SummonCreature{summon: %{entry: ^lord, position: ^position}}] =
                 run_on(player, steps, Context.new(0))
      end
    end

    test "the summoned lord faces its summoner, denounces them, then attacks after eight seconds" do
      player = character()
      guid = player.object.guid
      {:claim, steps, _action} = GameObjectScript.activated(@greater_wind_stone, 24_786, @stone_position)

      assert [%Effects.SummonCreature{summon: %{entry: 15_203}, steps: challenge, target_guid: ^guid}] =
               run_on(player, steps, Context.new(0))

      assert [
               %ScriptStep{command: :turn_to, delay_ms: 1_500},
               %ScriptStep{command: :talk, delay_ms: 1_600} = talk,
               %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x100, datalong3: 2, delay_ms: 8_000},
               %ScriptStep{command: :attack_start, delay_ms: 8_000}
             ] = challenge

      assert ScriptStep.talk_text_ids(talk) == [10_805, 10_806, 10_807, 10_810]
    end
  end

  describe "summon_entries/0" do
    test "lists every creature an object can call" do
      assert Enum.sort(GameObjectScript.summon_entries()) ==
               Enum.sort([11_876, 11_920, 14_748 | @treasure_hunters] ++ @abyssal_council)
    end
  end

  defp run_on(%Character{object: %Object{guid: guid}} = player, steps, context) do
    {player, _blackboard} = Script.run(player, Blackboard.new(), steps, guid, context)
    Enum.filter(player.internal.events, &match?(%Effects.SummonCreature{}, &1))
  end

  defp effects(entry, %Character{object: %Object{guid: guid}} = player, context \\ Context.new(0)) do
    object = Guid.from_low_guid(:game_object, entry, Unique.integer())
    steps = GameObjectScript.steps(entry, @cask_position)
    {player, _blackboard} = Script.run(player, Blackboard.new(), steps, object, context)

    player.internal.events
    |> Enum.filter(&(&1.__struct__ in [Effects.SummonCreature, Effects.ForwardScriptSteps]))
    |> tap(fn events -> Enum.each(events, &assert_targets(&1, guid, object)) end)
  end

  defp assert_targets(%Effects.SummonCreature{target_guid: target}, _guid, object), do: assert(target == object)
  defp assert_targets(_effect, _guid, _object), do: :ok

  defp character(opts \\ []) do
    quest_log =
      opts
      |> Keyword.get(:quests, [])
      |> Enum.with_index()
      |> Map.new(fn {{quest_id, status}, slot} -> {slot, %Entry{quest_id: quest_id, status: status}} end)

    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, Unique.integer())},
      unit: %Unit{race: 1, class: 1, health: 100, max_health: 100, auras: []},
      player: %Player{quest_log: quest_log, rewarded_quests: MapSet.new()},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(1), spellbook: %{}}
    }
  end
end
