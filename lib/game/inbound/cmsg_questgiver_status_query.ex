defmodule ThistleTea.Game.Inbound.CmsgQuestgiverStatusQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUESTGIVER_STATUS_QUERY

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Outbound

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    Outbound.send_packet(%Message.SmsgQuestgiverStatus{
      guid: guid,
      status: Quests.dialog_status(guid, c)
    })

    state
  end

  def handle(%__MODULE__{}, state), do: state
end
