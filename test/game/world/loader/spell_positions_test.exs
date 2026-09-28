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
      assert %{map: 0, orientation: orientation} = Spell.target_position(3561)
      assert_in_delta orientation, 5.28, 0.001
      assert %{map: 0, x: -6076.0, y: -215.0, z: 424.0} = Spell.target_position(18_634)
      assert %{map: 1, x: x, y: y, z: z} = Spell.target_position(23_442)
      assert_in_delta x, 6755.33, 0.01
      assert_in_delta y, -4658.09, 0.01
      assert_in_delta z, 724.8, 0.01

      for id <- [23_441, 23_446] do
        assert %{map: 1, x: x, y: y, z: z} = Spell.target_position(id)
        assert_in_delta x, -7109.1, 0.01
        assert_in_delta y, -3825.21, 0.01
        assert_in_delta z, 10.151, 0.01
      end

      assert Spell.target_position(987_654) == nil
    end
  end
end
