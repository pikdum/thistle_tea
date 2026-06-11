defmodule ThistleTea.Game.Network.Message.SmsgTrainerBuySucceeded do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TRAINER_BUY_SUCCEEDED

  defstruct [:trainer_guid, :spell_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{trainer_guid: trainer_guid, spell_id: spell_id}) do
    <<trainer_guid::little-size(64), spell_id::little-size(32)>>
  end
end
