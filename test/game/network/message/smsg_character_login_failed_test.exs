defmodule ThistleTea.Game.Network.Message.SmsgCharacterLoginFailedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCharacterLoginFailed

  describe "to_binary/1" do
    test "encodes the Vanilla login failure result" do
      message = %SmsgCharacterLoginFailed{result: SmsgCharacterLoginFailed.result(:failed)}

      assert SmsgCharacterLoginFailed.to_binary(message) == <<0x41>>
    end
  end
end
