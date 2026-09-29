defmodule ThistleTea.Game.Core.AI.GuardianScriptsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.Guardians
  alias ThistleTea.Game.Core.Pet.MiniPet

  describe "Script.run/5" do
    test "removes matching guardians from either unit owner without touching other companions" do
      for entity <- [%Mob{}, %Character{}] do
        source = %{entity | object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}

        source =
          source
          |> Guardians.activate(ref(2, 10))
          |> Guardians.activate(ref(3, 10))
          |> Guardians.activate(ref(4, 20))
          |> Companion.activate(:guardian, ref(5, 10))

        source = if is_struct(source, Character), do: MiniPet.activate(source, ref(6, 10)), else: source

        step = %ScriptStep{command: :remove_guardians, datalong: 10}
        {removed, blackboard} = Script.run(source, Blackboard.new(), [step], 99, 100)
        assert Guardians.active(removed) == [ref(4, 20)]
        assert Companion.active_guid(removed) == 5
        assert removed.internal.mini_pet == source.internal.mini_pet

        assert Enum.sort(removed.internal.events) ==
                 Enum.sort([%Effects.DespawnEntity{target_guid: 2}, %Effects.DespawnEntity{target_guid: 3}])

        assert Script.run(removed, blackboard, [step], 99, 100) == {removed, blackboard}

        {empty, _} = Script.run(removed, blackboard, [%{step | datalong: 0}], 99, 100)
        assert Guardians.active(empty) == []
        assert %Effects.DespawnEntity{target_guid: 4} in empty.internal.events
      end
    end

    test "rejects non-unit sources and honors the abort flag" do
      source = %GameObject{object: %Object{guid: 1}, internal: %Internal{}}

      for abort? <- [false, true] do
        step = %ScriptStep{command: :remove_guardians, datalong: 0, abort_on_failure?: abort?}
        {result, _, status} = Script.execute_step(source, Blackboard.new(), step, 99, Context.new(0))
        assert result == source
        assert status == if(abort?, do: :terminated, else: :continue)
      end
    end
  end

  defp ref(guid, entry), do: %EntityRef{guid: guid, entry: entry, spell_id: 500}
end
