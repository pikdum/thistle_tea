defmodule ThistleTea.Game.Network.Message.CmsgQuestlogRemoveQuest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTLOG_REMOVE_QUEST

  alias ThistleTea.Game.Player.Quests

  defstruct [:slot]

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, %{ready: true, character: %Character{}} = state) do
    Quests.abandon(state, slot)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<slot::size(8), _rest::binary>> = payload

    %__MODULE__{
      slot: slot
    }
  end
end
