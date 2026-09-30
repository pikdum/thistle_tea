defmodule ThistleTea.Game.Inbound.CmsgQuestgiverCancel do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUESTGIVER_CANCEL

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Quests

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{}} = state), do: Quests.cancel_dialog(state)

  def handle(%__MODULE__{}, state), do: state
end
