defmodule ThistleTea.Game.World.Loader.SpellGroupTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.StackRules
  alias ThistleTea.Game.World.Loader.SpellGroup

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads build-specific food, elixir, scroll, and cross-class conflicts" do
      previous = :ets.tab2list(SpellGroup)

      on_exit(fn ->
        :ets.delete_all_objects(SpellGroup)
        :ets.insert(SpellGroup, previous)
      end)

      assert :ok = SpellGroup.load_all()
      assert relation(18_192, 19_710) == :replace
      assert relation(19_710, 18_192) == :replace
      assert relation(11_390, 17_539) == :replace
      assert relation(17_539, 11_390) == :block
      assert relation(8118, 12_179) == :replace
      assert relation(12_179, 8118) == :block
      assert relation(99, 1160) == :replace
      assert relation(11_556, 9898) == :block
      assert relation(10_060, 12_042) == :replace
      assert relation(12_042, 10_060) == :block
      assert relation(19_740, 25_782) == :replace
      assert relation(2374, 17_539) == :none
      assert SpellGroup.get(0) == %StackRules{}
    end
  end

  defp relation(old, new) do
    StackRules.relation(%Spell{id: old, stack_rules: SpellGroup.get(old)}, %Spell{
      id: new,
      stack_rules: SpellGroup.get(new)
    })
  end
end
