defmodule ThistleTea.Game.Inbound.CmsgEmote do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_EMOTE

  alias ThistleTea.Game.World.Entity.Player.Emotes

  defstruct [:emote]

  @impl ClientMessage
  def from_binary(<<emote::little-size(32)>>), do: %__MODULE__{emote: emote}

  @impl ClientMessage
  def handle(%__MODULE__{emote: emote}, state), do: Emotes.command(state, emote)
end
