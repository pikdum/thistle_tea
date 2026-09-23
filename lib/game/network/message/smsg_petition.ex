defmodule ThistleTea.Game.Network.Message.SmsgPetitionShowlist do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PETITION_SHOWLIST

  defstruct [:npc_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{npc_guid: guid}) do
    <<guid::little-size(64), 1::8, 1::little-size(32), 5863::little-size(32), 16_161::little-size(32),
      1000::little-size(32), 1::little-size(32)>>
  end
end

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

defmodule ThistleTea.Game.Network.Message.SmsgPetitionQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PETITION_QUERY_RESPONSE

  alias ThistleTea.Game.Guild.Petitions.Petition

  defstruct [:petition]

  @impl ServerMessage
  def to_binary(%__MODULE__{petition: %Petition{} = petition}) do
    <<petition.id::little-size(32), petition.owner.guid::little-size(64)>> <>
      petition.name <>
      <<0, 0, 1::little-size(32), 9::little-size(32), 9::little-size(32), 0::little-size(32), 0::little-size(32),
        0::little-size(32), 0::little-size(32), 0::little-size(32), 0::little-size(16), 0::little-size(32),
        0::little-size(32), 0::little-size(32), 0::little-size(32)>>
  end
end

defmodule ThistleTea.Game.Network.Message.SmsgPetitionSignResults do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PETITION_SIGN_RESULTS

  defstruct [:item_guid, :signer_guid, :result]

  @results %{ok: 0, already_signed: 1, already_in_guild: 2, cant_sign_own: 3, need_more: 4}

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.item_guid::little-size(64), message.signer_guid::little-size(64),
      Map.fetch!(@results, message.result)::little-size(32)>>
  end
end

defmodule ThistleTea.Game.Network.Message.SmsgTurnInPetitionResults do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TURN_IN_PETITION_RESULTS

  defstruct [:result]

  @results %{ok: 0, already_in_guild: 2, need_more: 4}

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}), do: <<Map.fetch!(@results, result)::little-size(32)>>
end

defmodule ThistleTea.Game.Network.Message.MsgPetitionRenameServer do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_PETITION_RENAME

  defstruct [:item_guid, :name]

  @impl ServerMessage
  def to_binary(%__MODULE__{item_guid: item_guid, name: name}), do: <<item_guid::little-size(64)>> <> name <> <<0>>
end

defmodule ThistleTea.Game.Network.Message.MsgPetitionDeclineServer do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_PETITION_DECLINE

  defstruct [:signer_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{signer_guid: guid}), do: <<guid::little-size(64)>>
end
