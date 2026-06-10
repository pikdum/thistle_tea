defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverStatusQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_STATUS_QUERY

  alias ThistleTea.Game.Player.Quests

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    Network.send_packet(%Message.SmsgQuestgiverStatus{
      guid: guid,
      status: Quests.dialog_status(guid, c)
    })

    state
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
