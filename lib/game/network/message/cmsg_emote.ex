defmodule ThistleTea.Game.Network.Message.CmsgEmote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_EMOTE

  defstruct [:emote]

  @impl ClientMessage
  def from_binary(<<emote::little-size(32)>>), do: %__MODULE__{emote: emote}
end
