defmodule ThistleTea.Game.Network.Message.CmsgQuestlogRemoveQuest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTLOG_REMOVE_QUEST

  defstruct [:slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<slot::size(8), _rest::binary>> = payload

    %__MODULE__{
      slot: slot
    }
  end
end
