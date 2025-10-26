defmodule ThistleTea.Game.Message.SmsgNameQueryResponse do
  use ThistleTea.Game.ServerMessage, :SMSG_NAME_QUERY_RESPONSE

  defstruct [
    :guid,
    :character_name,
    :realm_name,
    :race,
    :gender,
    :class
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        guid: guid,
        character_name: character_name,
        realm_name: realm_name,
        race: race,
        gender: gender,
        class: class
      }) do
    <<guid::little-size(64)>> <>
      character_name <>
      <<0>> <>
      realm_name <>
      <<0>> <>
      <<race::little-size(32), gender::little-size(32), class::little-size(32)>>
  end
end
