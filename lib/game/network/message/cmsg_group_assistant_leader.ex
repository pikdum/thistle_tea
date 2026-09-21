defmodule ThistleTea.Game.Network.Message.CmsgGroupAssistantLeader do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_ASSISTANT_LEADER

  alias ThistleTea.Game.Player.Groups

  defstruct [:guid, :enabled?]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), flag::little-size(8)>>) do
    %__MODULE__{guid: guid, enabled?: flag != 0}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, enabled?: enabled?}, state), do: Groups.set_assistant(state, guid, enabled?)
end
