defmodule ThistleTea.Game.World.Loader.SpellEnvironmentDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Environment
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads outdoor requirements on mounts, forms, talents and item sets" do
      for id <- [458, 783, 2645, 17_002, 19_596, 23_218, 24_866] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :only_outdoors)
        assert Environment.validate(spell, false) == {:error, :only_outdoors}
        assert Environment.validate(spell, true) == :ok
      end

      for id <- [17_002, 19_596, 23_218, 24_866] do
        assert Environment.outdoor_passive?(SpellLoader.load(id))
      end

      refute Environment.restricted?(SpellLoader.load(768))
    end
  end
end
