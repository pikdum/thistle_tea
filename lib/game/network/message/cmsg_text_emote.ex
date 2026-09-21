defmodule ThistleTea.Game.Network.Message.CmsgTextEmote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TEXT_EMOTE

  alias ThistleTea.Game.Player.Emotes

  defstruct [:text_emote, :emote, :target]

  @impl ClientMessage
  def handle(%__MODULE__{text_emote: text_emote, emote: emote, target: target}, state) do
    Emotes.text(state, text_emote, emote, target)
  end

  @impl ClientMessage
  def from_binary(<<text_emote::little-size(32), emote::little-size(32), target::little-size(64)>>) do
    %__MODULE__{text_emote: text_emote, emote: emote, target: target}
  end
end
