defmodule ThistleTea.Game.World.Loader.SpellTargetLimitDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1 and build_spellbook/1" do
    test "retain vanilla rank-specific target limits and unlimited areas" do
      limits = [
        {1680, 4},
        {5246, 5},
        {5484, 5},
        {6343, 4},
        {8122, 2},
        {8124, 3},
        {10_888, 4},
        {10_890, 5},
        {11_581, 4},
        {17_928, 5},
        {20_549, 5},
        {24_083, 4},
        {122, 0},
        {10, 0}
      ]

      spellbook = SpellLoader.build_spellbook(Enum.map(limits, &elem(&1, 0)))

      for {id, limit} <- limits do
        assert SpellLoader.load(id).max_targets == limit
        assert spellbook[id].max_targets == limit
      end
    end
  end
end
