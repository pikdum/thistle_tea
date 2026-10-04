defmodule ThistleTea.Game.Core.AI.CreatureScript.TerenthisTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.Script
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

  @terenthis 3_693
  @sentinel_selarin 3_694

  describe "quest_end_steps/0" do
    test "either escape brings Sentinel Selarin in from the dock for two minutes" do
      %{994 => force, 995 => stealth} = CreatureScript.quest_end_steps()
      assert force == stealth

      [summon] = force

      assert {[%Effects.SummonCreature{summon: selarin}], _} = run(summon, :met)

      assert %{entry: @sentinel_selarin, despawn_type: 9, despawn_delay_ms: 120_000, position: {6_409.01, _, _, _}} =
               selarin
    end

    test "she is not called twice while she is still about" do
      [summon] = CreatureScript.quest_end_steps()[994]
      assert {[], _} = run(summon, :unmet)
    end

    test "Terenthis keeps his own AI" do
      refute CreatureScript.ported?(@terenthis)
      assert @sentinel_selarin in CreatureScript.summon_entries()
    end
  end

  defp run(summon, nobody_there) do
    player = Guid.from_low_guid(:player, Unique.integer())
    context = Context.new(0, script_conditions: %{summon.condition => nobody_there})
    {terenthis, blackboard} = Script.run(terenthis(), Blackboard.new(), [summon], player, context)
    {Enum.filter(terenthis.internal.events, &match?(%Effects.SummonCreature{}, &1)), blackboard}
  end

  defp terenthis do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @terenthis, Unique.integer()), entry: @terenthis},
      unit: %Unit{health: 100, max_health: 100, level: 20, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {6_405.0, 378.0, 13.8, 0.0}},
      internal: %Internal{world: WorldRef.open(1), name: "Terenthis", creature: %Creature{}, spellbook: %{}}
    }
  end
end
