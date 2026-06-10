defmodule ThistleTea.Game.World.Visibility.FilterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Visibility.Filter

  describe "living viewer" do
    test "sees normal mobs, alive or dead" do
      assert Filter.can_see?(false, :mob, %{alive?: true})
      assert Filter.can_see?(false, :mob, %{alive?: false})
    end

    test "does not see spirit healers" do
      refute Filter.can_see?(false, :mob, %{alive?: true, spirit_service?: true})
    end

    test "sees living and dead-unreleased players" do
      assert Filter.can_see?(false, :player, %{alive?: true})
      assert Filter.can_see?(false, :player, %{alive?: false, ghost?: false})
    end

    test "does not see ghost players" do
      refute Filter.can_see?(false, :player, %{alive?: false, ghost?: true})
    end

    test "sees corpses and game objects" do
      assert Filter.can_see?(false, :corpse, %{})
      assert Filter.can_see?(false, :game_object, %{})
    end
  end

  describe "ghost viewer" do
    test "sees all players" do
      assert Filter.can_see?(true, :player, %{alive?: true})
      assert Filter.can_see?(true, :player, %{ghost?: true})
    end

    test "sees spirit healers" do
      assert Filter.can_see?(true, :mob, %{alive?: true, spirit_service?: true})
    end

    test "sees ghost-visible creatures" do
      assert Filter.can_see?(true, :mob, %{alive?: true, ghost_visible?: true})
    end

    test "does not see normal living mobs away from own corpse" do
      refute Filter.can_see?(true, :mob, %{alive?: true})
      refute Filter.can_see?(true, :mob, %{alive?: true}, 100.0)
    end

    test "sees living mobs near own corpse" do
      assert Filter.can_see?(true, :mob, %{alive?: true}, 20.0)
      assert Filter.can_see?(true, :mob, %{alive?: true}, Filter.corpse_sight_range())
    end

    test "does not see dead mobs near own corpse" do
      refute Filter.can_see?(true, :mob, %{alive?: false}, 20.0)
    end

    test "sees corpses and game objects" do
      assert Filter.can_see?(true, :corpse, %{})
      assert Filter.can_see?(true, :game_object, %{})
    end
  end
end
