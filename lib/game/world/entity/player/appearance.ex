defmodule ThistleTea.Game.World.Entity.Player.Appearance do
  @moduledoc "Owner-local visual preferences, such as hiding the helm or cloak from the interface options."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Player.PlayerFlags

  def toggle_hidden(%{character: %Character{} = character} = state, slot) when slot in [:helm, :cloak] do
    %{state | character: PlayerFlags.toggle_hidden(character, slot)}
  end

  def toggle_hidden(state, _slot), do: state
end
