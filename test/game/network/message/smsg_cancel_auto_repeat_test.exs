defmodule ThistleTea.Game.Network.Message.SmsgCancelAutoRepeatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCancelAutoRepeat

  test "encodes the empty Vanilla payload" do
    assert SmsgCancelAutoRepeat.to_binary(%SmsgCancelAutoRepeat{}) == <<>>
  end
end
