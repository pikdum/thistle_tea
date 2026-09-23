defmodule ThistleTea.Game.World.Loader.SpellObjectTargetVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Spell.ObjectTargets.Selector
  alias ThistleTea.Game.World.Loader.GameObjectScript
  alias ThistleTea.Game.World.Loader.SpellObjectTarget

  @moduletag :vmangos_db

  setup do
    SpellObjectTarget.init()
    SpellObjectTarget.load_all()
    GameObjectScript.init()
    GameObjectScript.load_all()
    :ok
  end

  describe "get/1" do
    test "retains resolved conditions and per-effect masks" do
      assert [%Selector{entry: 175_124, condition: %Condition{entry: 15_958, type: :and, children: children}}] =
               SpellObjectTarget.get(15_958)

      assert Enum.any?(children, &match?(%Condition{type: :object_spawned}, &1))

      assert Enum.sort_by(SpellObjectTarget.get(24_973), & &1.entry) == [
               %Selector{entry: 180_449, inverse_effect_mask: 2},
               %Selector{entry: 180_450, inverse_effect_mask: 4}
             ]
    end

    test "caches door-use scripts by spawn ID" do
      assert [%ScriptStep{command: :open_door, datalong: 33_219} | _] = GameObjectScript.get(34_006)
    end
  end
end
