defmodule ThistleTea.Game.Network.Message.SmsgCooldownEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCooldownEvent

  test "encodes the spell and caster guid" do
    message = %SmsgCooldownEvent{spell_id: 1784, guid: 0x0102030405060708}

    assert SmsgCooldownEvent.to_binary(message) ==
             <<1784::little-size(32), 0x0102030405060708::little-size(64)>>
  end
end
