defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverStatusQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_STATUS_QUERY

  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    giver_quests =
      guid
      |> Guid.entry()
      |> QuestLoader.given_by()
      |> Enum.map(&QuestLoader.get/1)
      |> Enum.reject(&is_nil/1)

    status = QuestDialogStatus.for_giver(giver_quests, c.unit.level)

    Network.send_packet(%Message.SmsgQuestgiverStatus{guid: guid, status: status})

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
