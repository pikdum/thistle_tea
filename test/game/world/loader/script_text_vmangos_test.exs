defmodule ThistleTea.Game.World.Loader.ScriptTextVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.World.Loader.Script

  @moduletag :vmangos_db

  @come_see_the_nightmare 11_271
  @whisper 4

  describe "resolve_texts/1" do
    test "a talk step's chat type overrides its broadcast text's" do
      [stored, whispered] =
        Script.resolve_texts([
          %ScriptStep{command: :talk, dataint: @come_see_the_nightmare},
          %ScriptStep{command: :talk, datalong: @whisper, dataint: @come_see_the_nightmare}
        ])

      assert [%{chat_type: :yell, text: "Come, $n. See what the Nightmare brings..."}] = stored.texts
      assert [%{chat_type: :whisper, text: "Come, $n. See what the Nightmare brings..."}] = whispered.texts
    end
  end
end
