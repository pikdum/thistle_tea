defmodule ThistleTea.Game.Player.SpellsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Network.Message.SmsgSetProficiency
  alias ThistleTea.Game.Player.Spells

  describe "send_proficiencies/1" do
    test "advertises fishing-pole proficiency when Fishing is known" do
      character = %Character{
        player: %Player{skills: %{356 => %{value: 1, max: 75, range: :tier, always_max?: false}}},
        internal: %Internal{spellbook: %{}}
      }

      assert :ok = Spells.send_proficiencies(character)

      assert_received {:"$gen_cast", {:send_packet, %SmsgSetProficiency{item_class: 2, subclass_mask: mask}}}
      assert (mask &&& 1 <<< 20) != 0
      assert_received {:"$gen_cast", {:send_packet, %SmsgSetProficiency{item_class: 4}}}
    end
  end
end
