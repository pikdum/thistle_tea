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
