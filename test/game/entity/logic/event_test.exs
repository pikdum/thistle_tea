defmodule ThistleTea.Game.Entity.Logic.EventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Event

  describe "monster_move/1" do
    test "returns a monster movement event with packet options" do
      assert %Event{type: :monster_move, move_opts: [face_target: 1]} = Event.monster_move(face_target: 1)
    end
  end

  describe "spell_cast_result/1" do
    test "returns a spell cast result event" do
      assert %Event{type: :spell_cast_result, spell_id: 133} = Event.spell_cast_result(133)
    end
  end

  describe "spell_go/4" do
    test "returns a spell go event with resolved hits and raw targets" do
      assert %Event{
               type: :spell_go,
               source_guid: 1,
               spell_id: 133,
               hit_guids: [2],
               raw_targets: <<1, 2>>
             } = Event.spell_go(1, 133, [2], <<1, 2>>)
    end
  end

  describe "object_update/1" do
    test "returns an object update event" do
      assert %Event{type: :object_update, update_type: :values} = Event.object_update(:values)
    end
  end
end
