defmodule ThistleTea.Game.Core.Player.ActionButtons do
  @moduledoc """
  A player's action bar slots, stored as the client's packed button data:
  the action id in the low 24 bits and the button type in the high byte.

  `set/4` follows VMangos HandleSetActionButtonOpcode. Zero clears a slot.
  Spells must be known and not passive, items must exist (checked through
  the caller's `item_exists?` lookup), and macros are stored unchecked. Any
  other type, an out-of-range slot, or a failed check leaves the bar
  unchanged. The server never rewrites stored buttons on its own.
  """
  import Bitwise, only: [&&&: 2, >>>: 2]

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Spell

  @max_buttons 120

  @spell 0x00
  @macro 0x40
  @click_macro 0x41
  @item 0x80

  def max_buttons, do: @max_buttons

  def set(%Character{internal: %Internal{} = internal} = character, button, packed, item_exists?)
      when is_integer(button) and button >= 0 and button < @max_buttons and is_integer(packed) and
             is_function(item_exists?, 1) do
    buttons = internal.action_buttons || %{}

    cond do
      packed == 0 ->
        put_buttons(character, Map.delete(buttons, button))

      valid?(character, type(packed), action(packed), item_exists?) ->
        put_buttons(character, Map.put(buttons, button, packed))

      true ->
        character
    end
  end

  def set(character, _button, _packed, _item_exists?), do: character

  def action(packed), do: packed &&& 0x00FFFFFF

  def type(packed), do: packed >>> 24 &&& 0xFF

  defp valid?(%Character{internal: %Internal{spellbook: spellbook}}, @spell, spell_id, _item_exists?) do
    case spellbook do
      %{^spell_id => %Spell{} = spell} -> not Spell.attribute?(spell, :passive)
      _ -> false
    end
  end

  defp valid?(_character, @item, item_id, item_exists?), do: item_exists?.(item_id)
  defp valid?(_character, type, _action, _item_exists?) when type in [@macro, @click_macro], do: true
  defp valid?(_character, _type, _action, _item_exists?), do: false

  defp put_buttons(%Character{internal: internal} = character, buttons) do
    %{character | internal: %{internal | action_buttons: buttons}}
  end
end
