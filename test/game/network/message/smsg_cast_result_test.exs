defmodule ThistleTea.Game.Network.Message.SmsgCastResultTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCastResult
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area

  describe "to_binary/1" do
    test "includes the required area and safely encodes rules without a named area" do
      spell = %Spell{id: 6298, area_rules: [%Area{area_id: 148}]}

      assert SmsgCastResult.to_binary(SmsgCastResult.failure(spell, :requires_area)) ==
               <<6298::little-size(32), 2, 0x5D, 148::little-size(32)>>

      assert SmsgCastResult.to_binary(SmsgCastResult.failure(%Spell{id: 123}, :requires_area)) ==
               <<123::little-size(32), 2, 0x5D, 0::little-size(32)>>
    end

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
