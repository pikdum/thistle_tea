defmodule ThistleTea.Game.World.Entity.Player.Input do
  @moduledoc """
  Applies client input to a player. While another unit possesses the player,
  only messages that are `ThistleTea.Game.World.ClientInput.while_possessed?/1`
  get through.
  """

  alias ThistleTea.Game.Core.Pet.PlayerPossession
  alias ThistleTea.Game.World.ClientInput

  def handle(message, state) do
    if allowed?(message, state), do: ClientInput.handle(message, state), else: state
  end

  def allowed?(message, %{character: character}) do
    not PlayerPossession.active?(character) or ClientInput.while_possessed?(message)
  end

  def allowed?(_message, _state), do: true
end
