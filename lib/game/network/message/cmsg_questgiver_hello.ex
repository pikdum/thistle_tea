defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverHello do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_HELLO

  alias ThistleTea.Game.Player.Quests

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Quests.hello(state, guid)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
