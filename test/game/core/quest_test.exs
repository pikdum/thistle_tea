defmodule ThistleTea.Game.Core.QuestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Quest

  describe "allowed_in_raid?/1" do
    test "accepts the raid quest type or flag" do
      assert Quest.allowed_in_raid?(%Quest{type: 62})
      assert Quest.allowed_in_raid?(%Quest{flags: 0x40})
      refute Quest.allowed_in_raid?(%Quest{type: 1, flags: 0x20})
    end
  end

  describe "auto_complete?/1" do
    test "true only for method 0" do
      assert Quest.auto_complete?(%Quest{method: 0})
      refute Quest.auto_complete?(%Quest{method: 2})
    end
  end
end
