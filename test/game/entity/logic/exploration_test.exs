defmodule ThistleTea.Game.Entity.Logic.ExplorationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Logic.Exploration

  describe "discover/2" do
    test "sets the matching area bit in the 64-word client field" do
      {:ok, character} = Exploration.discover(character(), 33)

      assert byte_size(character.player.explored_zones) == 256
      assert binary_part(character.player.explored_zones, 0, 8) == <<0, 0, 0, 0, 2, 0, 0, 0>>
      assert Exploration.explored?(character, 33)
      refute Exploration.explored?(character, 32)
    end

    test "does not rediscover an unlocked area" do
      {:ok, character} = Exploration.discover(character(), 707)

      assert Exploration.discover(character, 707) == :already_explored
    end

    test "supports the first and last client bits" do
      {:ok, character} = Exploration.discover(character(), 0)
      {:ok, character} = Exploration.discover(character, 2047)

      assert Exploration.explored?(character, 0)
      assert Exploration.explored?(character, 2047)
      assert :binary.first(character.player.explored_zones) == 1
      assert :binary.last(character.player.explored_zones) == 0x80
    end

    test "rejects bits outside the client field" do
      assert Exploration.discover(character(), -1) == {:error, :invalid_area_bit}
      assert Exploration.discover(character(), 2048) == {:error, :invalid_area_bit}
    end
  end

  describe "unlock_all/1" do
    test "sets every client exploration word" do
      character = Exploration.unlock_all(character())

      assert character.player.explored_zones == :binary.copy(<<0xFF>>, 256)
    end
  end

  describe "experience/4" do
    test "uses the player's level plus five for much higher-level areas" do
      assert Exploration.experience(10, 25, 60, &base_xp/1) == 150
    end

    test "uses area XP within five levels" do
      assert Exploration.experience(20, 25, 60, &base_xp/1) == 250
      assert Exploration.experience(25, 25, 60, &base_xp/1) == 250
    end

    test "reduces XP by five percent per extra overlevel" do
      assert Exploration.experience(31, 25, 60, &base_xp/1) == 237
      assert Exploration.experience(50, 25, 60, &base_xp/1) == 0
    end

    test "awards no XP for zero-level areas or max-level players" do
      assert Exploration.experience(10, 0, 60, &base_xp/1) == 0
      assert Exploration.experience(60, 60, 60, &base_xp/1) == 0
    end
  end

  defp character do
    %Character{player: %Player{}}
  end

  defp base_xp(level), do: level * 10
end
