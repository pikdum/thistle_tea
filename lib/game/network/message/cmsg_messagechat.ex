defmodule ThistleTea.Game.Network.Message.CmsgMessagechat do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MESSAGECHAT

  alias ThistleTea.Game.Chat

  defstruct [:chat_type, :language, :message, :target_name]

  @chat_type_whisper 0x6
  @chat_type_channel 0x0E

  @impl ClientMessage
  def handle(%__MODULE__{chat_type: chat_type, language: language, message: message, target_name: target_name}, state) do
    Chat.handle(state, chat_type, language, message, target_name)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<chat_type::little-size(32), language::little-size(32), rest::binary>> = payload

    {target_name, rest} =
      if chat_type in [@chat_type_whisper, @chat_type_channel] do
        {:ok, target_name, rest} = BinaryUtils.parse_string(rest)
        {target_name, rest}
      else
        {nil, rest}
      end

    {:ok, message, _rest} = BinaryUtils.parse_string(rest)

    %__MODULE__{
      chat_type: chat_type,
      language: language,
      message: message,
      target_name: target_name
    }
  end
end
