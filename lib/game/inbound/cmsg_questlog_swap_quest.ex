defmodule ThistleTea.Game.Inbound.CmsgQuestlogSwapQuest do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUESTLOG_SWAP_QUEST

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Quests

  defstruct [:slot1, :slot2]

  @impl ClientMessage
  def from_binary(<<slot1::8, slot2::8, _rest::binary>>), do: %__MODULE__{slot1: slot1, slot2: slot2}

  @impl ClientMessage
  def handle(%__MODULE__{slot1: slot1, slot2: slot2}, %{ready: true, character: %Character{}} = state),
    do: Quests.swap_slots(state, slot1, slot2)

  def handle(%__MODULE__{}, state), do: state
end
