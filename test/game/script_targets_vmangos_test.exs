defmodule ThistleTea.Game.ScriptTargetsVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  @moduletag :vmangos_db

  describe "loaded source swaps" do
    test "New Year revelers turn both participants and delay the swapped talk emote" do
      assert [parent] = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [1_569_406])[1_569_406]
      assert parent.command == :start_script
      assert parent.target_type == :random_creature_with_entry
      assert parent.target_param1 == 15_694
      assert parent.target_param2 == 30
      assert parent.swap_final?
      steps = parent.sub_scripts[1_569_406]

      assert Enum.sort(Enum.map(steps, &{&1.command, &1.delay_ms, &1.swap_initial?})) == [
               {:emote, 1_000, true},
               {:turn_to, 0, false},
               {:turn_to, 0, true}
             ]

      source = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 15_694, 1)}, internal: %Internal{}}
      target = Guid.from_low_guid(:mob, 15_694, 2)
      {updated, _} = Script.run(source, Blackboard.new(), steps, target, 0)
      assert Enum.any?(updated.internal.events, &match?(%Effects.SetFacing{facing: {:target, ^target}}, &1))

      assert Enum.any?(updated.internal.events, fn
               %Effects.ForwardScriptSteps{target_guid: ^target, steps: [%ScriptStep{command: :turn_to}]} -> true
               _ -> false
             end)

      assert %Effects.ScriptSteps{duration_ms: 1_000, steps: [emote]} = List.last(updated.internal.events)
      assert emote.command == :emote
      assert emote.datalong == 1
      {due, _} = Script.run(source, Blackboard.new(), [emote], target, 1_000)

      assert [%Effects.ForwardScriptSteps{target_guid: ^target, steps: [%ScriptStep{command: :emote}]}] =
               due.internal.events
    end

    test "Estelle's gossip makes the player cast the tools conjure on themselves" do
      steps = ScriptLoader.load_by_ids(Mangos.GossipScript, [161])[161]
      step = Enum.find(steps, &(&1.command == :cast_spell and &1.datalong == 9_949))
      assert step.command == :cast_spell
      assert step.datalong == 9_949
      assert step.swap_initial?
      assert step.target_self?
      source = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 4_739, 1)}, internal: %Internal{}}
      player = %Character{object: %Object{guid: 2}, unit: %Unit{}, internal: %Internal{}}
      {source, _} = Script.execute_steps(source, Blackboard.new(), [step], player.object.guid, 0)
      assert [%Effects.ForwardScriptSteps{steps: steps, source_guid: provided}] = source.internal.events
      {player, _} = Script.run(player, Blackboard.new(), steps, provided, 0)

      assert [%Effects.ScriptedCast{entry: %{spell_id: 9_949}, target_guid: 2}] = player.internal.events
    end
  end
end
