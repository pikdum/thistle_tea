defmodule ThistleTea.Game.Message.SmsgTextEmote do
  use ThistleTea.Game.ServerMessage, :SMSG_TEXT_EMOTE

  defstruct [
    :guid,
    :text_emote,
    :emote,
    :name
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, text_emote: text_emote, emote: emote, name: name}) do
    name_length = String.length(name) + 1

    <<guid::little-size(64)>> <>
      <<text_emote::little-size(32)>> <>
      <<emote::little-size(32)>> <>
      <<name_length::little-size(32)>> <> name <> <<0>>
  end
end
