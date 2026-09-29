defmodule ThistleTea.Game.Network.Message.CmsgSetFactionInactive do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_FACTION_INACTIVE

  defstruct [:index, :inactive]

  @impl ClientMessage
  def from_binary(<<index::little-size(32), inactive>>) do
    %__MODULE__{index: index, inactive: inactive}
  end
end
