defmodule ThistleTea.Game.Network.Message.CmsgSetFactionAtwar do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_FACTION_ATWAR

  defstruct [:index, :flags]

  @impl ClientMessage
  def from_binary(<<index::little-size(32), flags>>) do
    %__MODULE__{index: index, flags: flags}
  end
end
