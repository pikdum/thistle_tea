defmodule ThistleTea.Game.Core.Player.ActionButtonsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Player.ActionButtons
  alias ThistleTea.Game.Core.Spell

  @spell 0x00
  @macro 0x40
  @click_macro 0x41
  @item 0x80

  setup [:character]

  describe "set/4" do
    test "stores known active spells, existing items, and macros", %{character: character} do
      character =
        character
        |> ActionButtons.set(0, packed(@spell, 133), &item?/1)
        |> ActionButtons.set(1, packed(@item, 6948), &item?/1)
        |> ActionButtons.set(2, packed(@macro, 3), &item?/1)
        |> ActionButtons.set(3, packed(@click_macro, 4), &item?/1)

      assert character.internal.action_buttons == %{
               0 => packed(@spell, 133),
               1 => packed(@item, 6948),
               2 => packed(@macro, 3),
               3 => packed(@click_macro, 4)
             }
    end

    test "rejects unknown or passive spells, missing items, and unknown types", %{character: character} do
      for packed <- [packed(@spell, 999), packed(@spell, 20_599), packed(@item, 1), packed(0x20, 133)] do
        assert ActionButtons.set(character, 5, packed, &item?/1) == character
      end
    end

    test "rejects out-of-range slots", %{character: character} do
      assert ActionButtons.set(character, ActionButtons.max_buttons(), packed(@spell, 133), &item?/1) == character
    end

    test "clears a slot with zero", %{character: character} do
      stored = ActionButtons.set(character, 7, packed(@spell, 133), &item?/1)

      assert ActionButtons.set(stored, 7, 0, &item?/1).internal.action_buttons == %{}
    end
  end

  describe "action/1 and type/1" do
    test "unpack the action id and button type" do
      assert ActionButtons.action(packed(@item, 6948)) == 6948
      assert ActionButtons.type(packed(@item, 6948)) == @item
    end
  end

  defp packed(type, action), do: Bitwise.bsl(type, 24) + action

  defp item?(entry), do: entry == 6948

  defp character(_context) do
    spellbook = %{
      133 => %Spell{id: 133},
      20_599 => %Spell{id: 20_599, attributes: MapSet.new([:passive])}
    }

    %{character: %Character{internal: %Internal{spellbook: spellbook, action_buttons: %{}}}}
  end
end
