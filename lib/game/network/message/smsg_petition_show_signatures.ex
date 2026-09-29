defmodule ThistleTea.Game.Network.Message.SmsgPetitionShowSignatures do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PETITION_SHOW_SIGNATURES

  alias ThistleTea.Game.Guild.Petitions.Petition

  defstruct [:petition]

  @impl ServerMessage
  def to_binary(%__MODULE__{petition: %Petition{} = petition}) do
    signatures =
      petition.signatures
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&<<&1::little-size(64), 0::little-size(32)>>)

    <<petition.item_guid::little-size(64), petition.owner.guid::little-size(64), petition.id::little-size(32),
      map_size(petition.signatures)::8>> <> IO.iodata_to_binary(signatures)
  end
end
