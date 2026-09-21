defmodule ThistleTea.Game.Entity.Logic.GameObjectInteractionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.GameObjectInteraction

  describe "within?/6" do
    test "uses three-dimensional origin distance without display bounds" do
      assert within?({3.0, 4.0, 0.0}, nil)
      refute within?({3.0, 4.0, 0.1}, nil)
      refute within?({0.0, 0.0, 5.1}, nil)
    end

    test "expands scaled bounds by an unscaled interaction radius" do
      bounds = {{-2.0, -1.0, 0.0}, {4.0, 1.0, 3.0}}
      assert within?({13.0, 0.0, 0.0}, bounds, 2.0)
      refute within?({13.1, 0.0, 0.0}, bounds, 2.0)
      assert within?({0.0, 0.0, 11.0}, bounds, 2.0)
      refute within?({0.0, 0.0, 11.1}, bounds, 2.0)
    end

    test "rotates asymmetric bounds around all three axes" do
      bounds = {{-1.0, -1.0, -1.0}, {10.0, 1.0, 1.0}}
      half = :math.sqrt(0.5)
      assert within?({0.0, 14.0, 0.0}, bounds, 1.0, {0.0, 0.0, half, half})
      refute within?({14.0, 0.0, 0.0}, bounds, 1.0, {0.0, 0.0, half, half})
      assert within?({0.0, 0.0, -14.0}, bounds, 1.0, {0.0, half, 0.0, half})
      refute within?({0.0, 0.0, 14.0}, bounds, 1.0, {0.0, half, 0.0, half})
    end

    test "translates the origin and tolerates an empty quaternion or degenerate bounds" do
      assert GameObjectInteraction.within?({12, 20, 30}, {10, 20, 30}, {0, 0, 0, 0}, 1, nil, 2)
      assert within?({5.0, 0.0, 0.0}, {{0, 0, 0}, {0, 0, 0}})
      refute within?({5.1, 0.0, 0.0}, {{0, 0, 0}, {0, 0, 0}})
      assert within?({14.0, 0.0, 0.0}, {{0, 0, 0}, {10, 0, 0}})
    end
  end

  defp within?(position, bounds, scale \\ 1.0, rotation \\ {0.0, 0.0, 0.0, 1.0}) do
    GameObjectInteraction.within?(position, {0.0, 0.0, 0.0}, rotation, scale, bounds, 5.0)
  end
end
