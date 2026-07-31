defmodule ThistleTea.Game.Network.Message.SmsgQuestupdateFailedtimerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgQuestupdateFailedtimer

  test "encodes the failed quest id" do
    assert SmsgQuestupdateFailedtimer.to_binary(%SmsgQuestupdateFailedtimer{quest_id: 986}) ==
             <<986::little-size(32)>>
  end
end
