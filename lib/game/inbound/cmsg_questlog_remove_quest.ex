defmodule ThistleTea.Game.Inbound.CmsgQuestlogRemoveQuest do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUESTLOG_REMOVE_QUEST

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Quests

  defstruct [:slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<slot::size(8), _rest::binary>> = payload

    %__MODULE__{
      slot: slot
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, %{ready: true, character: %Character{}} = state) do
    Quests.abandon(state, slot)
  end

  def handle(%__MODULE__{}, state), do: state
end
