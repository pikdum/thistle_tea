defmodule ThistleTea.Game.Network.Message.SmsgQuestupdateFailedtimer do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTUPDATE_FAILEDTIMER

  defstruct [:quest_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{quest_id: quest_id}) do
    <<quest_id::little-size(32)>>
  end
end
