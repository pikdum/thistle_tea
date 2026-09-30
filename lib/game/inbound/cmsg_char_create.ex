defmodule ThistleTea.Game.Inbound.CmsgCharCreate do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHAR_CREATE

  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader
  alias ThistleTea.Game.World.Outbound

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

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Logger.info("CMSG_CHAR_CREATE: #{message.name}")

    character = CharacterLoader.build(message, state.account.id)

    case Characters.create(character) do
      {:error, :character_exists} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x31})

      {:error, :character_limit} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x35})

      {:ok, _} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x2E})
    end

    state
  end
end
