defmodule ThistleTea.Game.Network.Message.CmsgCharCreate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHAR_CREATE

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Characters
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader

  require Logger

  defstruct [
    :name,
    :race,
    :class,
    :gender,
    :skin_color,
    :face,
    :hair_style,
    :hair_color,
    :facial_hair,
    :outfit_id
  ]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Logger.info("CMSG_CHAR_CREATE: #{message.name}")

    character = CharacterLoader.build(message, state.account.id)

    case Characters.create(character) do
      {:error, :character_exists} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x31})

      {:error, :character_limit} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x35})

      {:ok, _} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x2E})
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    with {:ok, name, rest} <- BinaryUtils.parse_string(payload),
         <<race, class, gender, skin_color, face, hair_style, hair_color, facial_hair, outfit_id>> <- rest do
      %__MODULE__{
        name: String.capitalize(name),
        race: race,
        class: class,
        gender: gender,
        skin_color: skin_color,
        face: face,
        hair_style: hair_style,
        hair_color: hair_color,
        facial_hair: facial_hair,
        outfit_id: outfit_id
      }
    end
  end
end
