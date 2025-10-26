defmodule ThistleTea.Game.Message.SmsgEmote do
  use ThistleTea.Game.ServerMessage, :SMSG_EMOTE

  defstruct [
    :emote,
    :guid
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{emote: emote, guid: guid}) do
    <<emote::little-size(32), guid::little-size(64)>>
  end
end
