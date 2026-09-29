defmodule ThistleTea.Game.Network.Message.CmsgCharCreate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHAR_CREATE

  alias ThistleTea.Game.Network.Message

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
end
