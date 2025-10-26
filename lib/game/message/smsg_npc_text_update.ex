defmodule ThistleTea.Game.Message.SmsgNpcTextUpdate do
  use ThistleTea.Game.ServerMessage, :SMSG_NPC_TEXT_UPDATE

  defstruct [
    :text_id,
    :texts
  ]

  defmodule NpcTextUpdateEmote do
    defstruct [:delay, :emote]
  end

  defmodule NpcTextUpdate do
    defstruct [:probability, :texts, :language, :emotes]
  end

  @impl ServerMessage
  def to_binary(%__MODULE__{
        text_id: text_id,
        texts: texts
      }) do
    <<text_id::little-size(32)>> <>
      Enum.map_join(texts, fn text ->
        <<text.probability::little-float-size(32)>> <>
          Enum.map_join(text.texts, fn t ->
            if t, do: t <> <<0>>, else: <<0>>
          end) <>
          <<text.language::little-size(32)>> <>
          Enum.map_join(text.emotes, fn emote ->
            <<emote.delay::little-size(32), emote.emote::little-size(32)>>
          end)
      end)
  end
end
