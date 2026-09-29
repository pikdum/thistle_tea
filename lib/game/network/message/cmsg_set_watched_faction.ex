defmodule ThistleTea.Game.Network.Message.CmsgSetWatchedFaction do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_WATCHED_FACTION

  defstruct [:index]

  @impl ClientMessage
  def from_binary(<<index::little-signed-size(32)>>) do
    %__MODULE__{index: index}
  end
end
