defmodule ThistleTea.Game.Entity.Server.GameObject.ChairTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Chair, as: ChairConfig
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Server.GameObject.Chair

  describe "seat/3" do
    test "selects the nearest slot and applies the configured chair height" do
      chair = chair(slots: 3, height: 1, size: 2.0, position: {10.0, 20.0, 4.0, 0.0})

      assert {:ok, {seat_x, seat_y, 4.0, orientation}, 5} = Chair.seat(chair, 0, {10.0, 22.2, 4.0})
      assert_in_delta seat_x, 10.0, 0.0001
      assert_in_delta seat_y, 22.0, 0.0001
      assert_in_delta orientation, 0.0, 0.0001
    end

    test "uses the object center when the template has no slots" do
      chair = chair(slots: 0, position: {10.0, 20.0, 4.0, 1.0})

      assert {:ok, {10.0, 20.0, 4.0, 1.0}, 4} = Chair.seat(chair, 0, {10.0, 20.0, 4.0})
    end

    test "rejects a player farther than three yards from the nearest slot" do
      chair = chair(slots: 1, position: {10.0, 20.0, 4.0, 0.0})

      assert {:error, :too_far} = Chair.seat(chair, 0, {14.0, 20.0, 4.0})
    end

    test "rejects players on another map" do
      assert {:error, :not_a_chair} = Chair.seat(chair(), 1, {10.0, 20.0, 4.0})
    end
  end

  defp chair(opts \\ []) do
    slots = Keyword.get(opts, :slots, 1)
    height = Keyword.get(opts, :height, 0)
    size = Keyword.get(opts, :size, 1.0)
    position = Keyword.get(opts, :position, {10.0, 20.0, 4.0, 0.0})

    %GameObject{
      object: %Object{scale_x: size},
      internal: %Internal{map: 0, chair: %ChairConfig{slots: slots, height: height}},
      movement_block: %MovementBlock{position: position}
    }
  end
end
