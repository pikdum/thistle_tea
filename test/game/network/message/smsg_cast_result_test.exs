defmodule ThistleTea.Game.Network.Message.SmsgCastResultTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCastResult
  alias ThistleTea.Game.Spell

  describe "to_binary/1" do
    test "encodes missing edible corpses" do
      message = SmsgCastResult.failure(20_577, :no_edible_corpses)
      assert SmsgCastResult.to_binary(message) == <<20_577::little-size(32), 2, 0x86>>
    end

    test "includes the required spell focus identifier" do
      message = SmsgCastResult.failure(%Spell{id: 2657, required_focus_id: 3}, :requires_spell_focus)
      assert SmsgCastResult.to_binary(message) == <<2657::little-size(32), 2, 0x5E, 3::little-size(32)>>
    end

    test "encodes disarmed weapon failures without item-class payloads" do
      message = SmsgCastResult.failure(78, :equipped_item)
      assert SmsgCastResult.to_binary(message) == <<78::little-size(32), 2, 0x18>>
    end
  end
end
