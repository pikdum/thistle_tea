defmodule ThistleTea.Game.Network.Message.CmsgEmote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_EMOTE

  alias ThistleTea.Game.Player.Emotes

  defstruct [:emote]

  @impl ClientMessage
  def handle(%__MODULE__{emote: emote}, state), do: Emotes.command(state, emote)

  @impl ClientMessage
  def from_binary(<<emote::little-size(32)>>), do: %__MODULE__{emote: emote}
end
