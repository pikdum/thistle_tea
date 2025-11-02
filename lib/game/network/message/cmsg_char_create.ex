defmodule ThistleTea.Game.Network.Message.CmsgCharCreate do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHAR_CREATE

  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Util

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

    character =
      message
      |> ThistleTea.Character.build(state.account.id)
      |> ThistleTea.Character.generate_and_assign_equipment()

    case ThistleTea.Character.create(character) do
      {:error, :character_exists} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x31})

      {:error, :character_limit} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x35})

      {:error, _} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x30})

      {:ok, _} ->
        Network.send_packet(%Message.SmsgCharCreate{result: 0x2E})
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    with {:ok, name, rest} <- Util.parse_string(payload),
         <<race, class, gender, skin_color, face, hair_style, hair_color, facial_hair, outfit_id>> <- rest do
      %__MODULE__{
        name: name,
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

  def generate_random_equipment do
    %{
      head: ItemTemplate.random_by_type(1),
      neck: ItemTemplate.random_by_type(2),
      shoulders: ItemTemplate.random_by_type(3),
      body: ItemTemplate.random_by_type(4),
      chest: ItemTemplate.random_by_type(5),
      waist: ItemTemplate.random_by_type(6),
      legs: ItemTemplate.random_by_type(7),
      feet: ItemTemplate.random_by_type(8),
      wrists: ItemTemplate.random_by_type(9),
      hands: ItemTemplate.random_by_type(10),
      finger1: ItemTemplate.random_by_type(11),
      finger2: ItemTemplate.random_by_type(11),
      trinket1: ItemTemplate.random_by_type(12),
      trinket2: ItemTemplate.random_by_type(12),
      back: ItemTemplate.random_by_type(16),
      mainhand: ItemTemplate.random_by_type(13),
      offhand: ItemTemplate.random_by_type(13),
      tabard: ItemTemplate.random_by_type(19)
    }
  end
end
