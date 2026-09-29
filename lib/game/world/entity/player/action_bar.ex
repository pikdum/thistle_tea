defmodule ThistleTea.Game.World.Entity.Player.ActionBar do
  @moduledoc """
  Applies a player's action bar edits: button slots validated against the
  spellbook and the cached item templates, and the visible bar toggles.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Player.ActionButtons
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  def set_button(%{character: %Character{} = character} = state, button, packed) do
    %{state | character: ActionButtons.set(character, button, packed, &item_exists?/1)}
  end

  def set_button(state, _button, _packed), do: state

  def set_toggles(%{character: %Character{player: %Player{} = player} = character} = state, action_bars) do
    %{state | character: %{character | player: %{player | action_bars: action_bars}}}
  end

  def set_toggles(state, _action_bars), do: state

  defp item_exists?(entry), do: match?(%ItemTemplate{}, ItemLoader.get_template(entry))
end
