defmodule ThistleTea.Game.World.Loader.ScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  describe "resolve_code_steps/1" do
    test "keeps the literal texts of a talk step that names no broadcast text" do
      text = %{text: "Something is very, very angry.", chat_type: :text_emote, language: 0, emote_id: 0}
      talk = %ScriptStep{command: :talk, texts: [text]}
      timed = %ScriptStep{command: :start_script, sub_scripts: %{1 => [talk]}}

      assert [^talk, ^timed] = ScriptLoader.resolve_code_steps([talk, timed])
    end
  end
end
