defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverQuestInvalidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgQuestgiverQuestInvalid

  test "encodes the reason as a little-endian integer" do
    assert SmsgQuestgiverQuestInvalid.to_binary(%SmsgQuestgiverQuestInvalid{reason: 0}) == <<0, 0, 0, 0>>

    assert SmsgQuestgiverQuestInvalid.to_binary(%SmsgQuestgiverQuestInvalid{reason: 0x12345678}) ==
             <<0x78, 0x56, 0x34, 0x12>>
  end
end
