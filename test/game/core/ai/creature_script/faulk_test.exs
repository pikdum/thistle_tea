defmodule ThistleTea.Game.Core.AI.CreatureScript.FaulkTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @henze_faulk 6172
  @narm_faulk 6177
  @symbol_of_life 8593

  describe "events/1" do
    test "both fallen paladins thank whoever raises them with the Symbol of Life" do
      for entry <- [@henze_faulk, @narm_faulk] do
        assert CreatureScript.ported?(entry)

        assert [%{event_type: :hit_by_spell, param1: @symbol_of_life, actions: [[%ScriptStep{} = thanks]]}] =
                 CreatureScript.events(entry)

        assert %ScriptStep{command: :talk, dataint: 2281} = thanks
      end
    end
  end
end
