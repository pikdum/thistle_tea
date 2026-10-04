defmodule ThistleTea.Game.Core.AI.CreatureScript.DireMaulTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @mizzle 14_353

  describe "events/1" do
    test "Mizzle hails the new king, walks to the throne, and only then offers to talk" do
      assert CreatureScript.ported?(@mizzle)

      assert [
               %{event_type: :spawned, actions: [[home, walk, hail]]},
               %{event_type: :reached_home, repeatable?: false, actions: [[at_throne, gossip]]}
             ] = CreatureScript.events(@mizzle)

      assert %ScriptStep{command: :set_home_position, position: {816.30, 481.80, 37.30, 3.17}} = home
      assert %ScriptStep{command: :movement, datalong: 7} = walk
      assert %ScriptStep{command: :talk, dataint: 9_348} = hail
      assert %ScriptStep{command: :talk, dataint: 9_411} = at_throne
      assert %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x1, datalong3: 1} = gossip
    end
  end
end
