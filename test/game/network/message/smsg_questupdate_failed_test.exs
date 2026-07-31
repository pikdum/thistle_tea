defmodule ThistleTea.Game.Network.Message.SmsgQuestupdateFailedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgQuestupdateFailed

  test "encodes the failed quest id" do
    assert SmsgQuestupdateFailed.to_binary(%SmsgQuestupdateFailed{quest_id: 986}) ==
             <<986::little-size(32)>>
  end
end
