defmodule ThistleTea.Game.Inbound.CmsgQuestgiverHello do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUESTGIVER_HELLO

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Quests

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Quests.hello(state, guid)
  end

  def handle(%__MODULE__{}, state), do: state
end
