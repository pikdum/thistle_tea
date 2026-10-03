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

  describe "summon_entries/0" do
    test "lists every creature an object can call" do
      assert Enum.sort(GameObjectScript.summon_entries()) == Enum.sort([11_876, 11_920, 14_748 | @treasure_hunters])
    end
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
