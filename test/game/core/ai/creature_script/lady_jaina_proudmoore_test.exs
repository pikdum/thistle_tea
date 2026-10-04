defmodule ThistleTea.Game.Core.AI.CreatureScript.LadyJainaProudmooreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @jaina 4_968

  describe "gossip/0" do
    test "greets by Missing Diplomat progress and offers the autograph to a player on the errand" do
      assert %{@jaina => %Gossip{texts: [welcome, hendel], options: [autograph]}} = CreatureScript.gossip()

      assert %Gossip.Text{text_id: 3_157, condition: nil} = welcome
      assert %Gossip.Text{text_id: 3_158, condition: %Condition{type: :or, children: [rewarded, complete]}} = hendel
      assert %Condition{type: :quest_rewarded, value1: 1_267} = rewarded
      assert %Condition{type: :quest_taken, value1: 1_267, value2: 2} = complete

      assert %Gossip.Option{
               condition: %Condition{type: :quest_taken, value1: 558, value2: 1},
               reply_text_id: 7_012,
               steps: [signing]
             } = autograph

      assert %ScriptStep{command: :cast_spell, datalong: 23_122, swap_final?: true, target_self?: true} = signing
    end

    test "the player, not Jaina, casts the autograph on themselves" do
      jaina = jaina()
      player = Guid.from_low_guid(:player, Unique.integer())
      %{@jaina => %Gossip{options: [%Gossip.Option{steps: steps}]}} = CreatureScript.gossip()

      {jaina, _blackboard} = Script.run(jaina, Blackboard.new(), steps, player, Context.new(0))

      assert [%Effects.ForwardScriptSteps{target_guid: ^player, source_guid: ^player, steps: [cast]}] =
               jaina.internal.events

      assert %ScriptStep{command: :cast_spell, datalong: 23_122} = cast
    end
  end

  describe "events/1" do
    test "she calls water elementals only while none are near" do
      [_aggro, _spells, %{actions: [[%ScriptStep{sub_scripts: specials}]]}] = CreatureScript.events(@jaina)

      assert [%ScriptStep{datalong: 20_681, target_self?: true, condition: none_near}] = specials[1]
      assert %Condition{type: :nearby_creature, value1: 10_955, reverse?: true} = none_near
    end

    test "a teleported victim leaves her threat list only when she is far from her tower" do
      [_aggro, _spells, %{actions: [[%ScriptStep{sub_scripts: specials}]]}] = CreatureScript.events(@jaina)

      assert [%ScriptStep{datalong: 20_682, target_type: :victim}, drop] = specials[2]

      assert %ScriptStep{command: :modify_threat, datalong: 1, position: {-101.0, _, _, _}, condition: far} = drop
      assert %Condition{type: :distance_to_position, value4: 40, swap_targets?: true, reverse?: true} = far
    end

    test "her timers wait while she is casting" do
      [_aggro, spells, special] = CreatureScript.events(@jaina)

      assert spells.not_casting?
      assert special.not_casting?
    end

    test "her spells go at her victim or a random attacker" do
      [_aggro, %{actions: [[%ScriptStep{sub_scripts: spells}]]}, _special] = CreatureScript.events(@jaina)

      assert spells |> Map.values() |> List.flatten() |> Enum.map(&{&1.datalong, &1.target_type}) == [
               {20_678, :victim},
               {20_679, :victim},
               {20_680, :hostile_random}
             ]
    end
  end

  defp jaina do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @jaina, Unique.integer()), entry: @jaina},
      unit: %Unit{health: 100, max_health: 100, level: 62, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {-4_018.1, -4_525.24, 12.0, 0.0}},
      internal: %Internal{world: WorldRef.open(1), name: "Lady Jaina Proudmoore", creature: %Creature{}, spellbook: %{}}
    }
  end
end
