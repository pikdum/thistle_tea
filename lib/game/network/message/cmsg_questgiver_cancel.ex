defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverCancel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_CANCEL

  alias ThistleTea.Game.Player.Quests

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{}} = state), do: Quests.cancel_dialog(state)

  def handle(_message, state), do: state
end
