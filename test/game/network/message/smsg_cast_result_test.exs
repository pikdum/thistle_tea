defmodule ThistleTea.Game.Network.Message.SmsgCastResultTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgCastResult
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area

  describe "to_binary/1" do
    test "encodes indoor and outdoor failures without extra payloads" do
      for {reason, code} <- [only_indoors: 0x52, only_outdoors: 0x55] do
        assert SmsgCastResult.to_binary(SmsgCastResult.failure(783, reason)) == <<783::little-size(32), 2, code>>
      end
    end

    test "encodes ID-only failures with unknown requirements" do
      for {reason, payload} <- [
            requires_area: <<0::little-size(32)>>,
            requires_spell_focus: <<0::little-size(32)>>,
            equipped_item_class: <<-1::little-size(32), 0::little-size(32), 0::little-size(32)>>
          ] do
        code = SmsgCastResult.reason_code(reason)

        assert SmsgCastResult.to_binary(SmsgCastResult.failure(123, reason)) ==
                 <<123::little-size(32), 2, code>> <> payload
      end
    end

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
