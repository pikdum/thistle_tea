defmodule ThistleTea.Game.Network.Message.CmsgTrainerBuySpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TRAINER_BUY_SPELL

  defstruct [:trainer_guid, :spell_id]

  @impl ClientMessage
  def from_binary(<<trainer_guid::little-size(64), spell_id::little-size(32)>>) do
    %__MODULE__{trainer_guid: trainer_guid, spell_id: spell_id}
  end
end
