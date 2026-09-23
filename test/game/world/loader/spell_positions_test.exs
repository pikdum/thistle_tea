defmodule ThistleTea.Game.World.Loader.SpellPositionsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell

  @moduletag :vmangos_db

  describe "load_target_positions/0" do
    test "caches summon and ordinary teleport destinations" do
      pattern = {{:target_position, :_}, :_}
      previous = :ets.match_object(Spell, pattern)

      on_exit(fn ->
        :ets.match_delete(Spell, pattern)
        :ets.insert(Spell, previous)
      end)

      assert Spell.load_target_positions() == :ok
      assert %{map: 309, x: x, y: y, z: 90.0} = Spell.target_position(24_466)
      assert_in_delta x, -11_582.9, 0.01
      assert_in_delta y, -1251.15, 0.01
      assert %{map: 1} = Spell.target_position(22_951)
      assert %{map: 0} = Spell.target_position(3561)
      assert Spell.target_position(987_654) == nil
    end
  end
end
