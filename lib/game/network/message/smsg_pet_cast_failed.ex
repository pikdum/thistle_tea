defmodule ThistleTea.Game.Network.Message.SmsgPetCastFailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_CAST_FAILED

  alias ThistleTea.Game.Network.Message.SmsgCastResult

  @spell_result_status_fail 2

  defstruct [:spell_id, :reason]

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id, reason: reason}) do
    <<spell_id::little-size(32), @spell_result_status_fail::little-size(8),
      SmsgCastResult.reason_code(reason)::little-size(8)>>
  end
end
