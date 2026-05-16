defmodule ThistleTea.Game.Entity.Logic.EventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Event

  describe "monster_move/1" do
    test "returns a monster movement event with packet options" do
      assert %Event{type: :monster_move, move_opts: [face_target: 1]} = Event.monster_move(face_target: 1)
    end
  end
end
