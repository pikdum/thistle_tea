defmodule ThistleTea.Game.Player.ChatStatus do
  @moduledoc """
  Player-owner boundary for chat availability and AFK battleground departure.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.ChatStatus
  alias ThistleTea.Game.Player.Battlegrounds

  def change(%{ready: true, character: %Character{} = previous} = state, mode, message) do
    character = ChatStatus.change(previous, mode, message)
    state = %{state | character: character}

    if previous.internal.chat_status.mode != :afk and character.internal.chat_status.mode == :afk do
      Battlegrounds.leave(state)
    else
      state
    end
  end

  def change(state, _mode, _message), do: state
end
