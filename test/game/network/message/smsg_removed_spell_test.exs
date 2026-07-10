defmodule ThistleTea.Game.Network.Message.SmsgRemovedSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgRemovedSpell

  describe "to_binary/1" do
    test "encodes the vanilla 16-bit spell id" do
      assert SmsgRemovedSpell.to_binary(%SmsgRemovedSpell{spell_id: 11_550}) == <<11_550::little-size(16)>>
    end
  end
end
