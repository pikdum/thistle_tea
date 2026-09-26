defmodule ThistleTea.Game.Entity.Logic.GuardianScriptsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Guardians
  alias ThistleTea.Game.Entity.Logic.MiniPet

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
