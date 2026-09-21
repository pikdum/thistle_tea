defmodule ThistleTea.Game.Entity.Logic.ChatStatus do
  @moduledoc """
  Pure AFK and DND transitions with public player-flag projection.
  """

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ChatStatus
  alias ThistleTea.Game.Entity.Logic.Core

  def change(%Character{internal: %{in_combat: true}} = character, :afk, _message), do: character

  def change(%Character{} = character, mode, message) when mode in [:afk, :dnd] and is_binary(message) do
    status = character.internal.chat_status

    status =
      if status.mode == mode and message == "",
        do: %ChatStatus{},
        else: %ChatStatus{mode: mode, message: message}

    put(character, status)
  end

  def reset(%Character{} = character), do: put(character, %ChatStatus{})

  def tag(%Character{internal: internal}), do: tag(internal.chat_status)
  def tag(%ChatStatus{mode: :afk}), do: 1
  def tag(%ChatStatus{mode: :dnd}), do: 2
  def tag(_status), do: 0

  defp put(character, status) do
    flags = (character.player.flags || 0) &&& bnot(0x06)
    flags = flags ||| player_flag(status.mode)

    if character.internal.chat_status == status and character.player.flags == flags do
      character
    else
      %{character | internal: %{character.internal | chat_status: status}, player: %{character.player | flags: flags}}
      |> Core.mark_broadcast_update()
    end
  end

  defp player_flag(:afk), do: 0x02
  defp player_flag(:dnd), do: 0x04
  defp player_flag(:available), do: 0
end
