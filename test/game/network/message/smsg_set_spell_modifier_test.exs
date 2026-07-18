defmodule ThistleTea.Game.Network.Message.SmsgSetSpellModifierTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSetFlatSpellModifier
  alias ThistleTea.Game.Network.Message.SmsgSetPctSpellModifier

  test "encodes flat modifiers with signed values" do
    message = %SmsgSetFlatSpellModifier{effect_index: 5, operation: 10, value: -500}

    assert SmsgSetFlatSpellModifier.to_binary(message) == <<5, 10, -500::little-signed-size(32)>>
  end

  test "encodes percent modifiers with signed values" do
    message = %SmsgSetPctSpellModifier{effect_index: 30, operation: 10, value: -100}

    assert SmsgSetPctSpellModifier.to_binary(message) == <<30, 10, -100::little-signed-size(32)>>
  end
end
