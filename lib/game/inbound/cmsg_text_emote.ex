defmodule ThistleTea.Game.Inbound.CmsgTextEmote do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_TEXT_EMOTE

  alias ThistleTea.Game.World.Entity.Player.Emotes

  defstruct [:text_emote, :emote, :target]

  @impl ClientMessage
  def from_binary(<<text_emote::little-size(32), emote::little-size(32), target::little-size(64)>>) do
    %__MODULE__{text_emote: text_emote, emote: emote, target: target}
  end

  @impl ClientMessage
  def handle(%__MODULE__{text_emote: text_emote, emote: emote, target: target}, state) do
    Emotes.text(state, text_emote, emote, target)
  end
end
