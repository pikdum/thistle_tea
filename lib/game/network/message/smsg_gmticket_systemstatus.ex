defmodule ThistleTea.Game.Network.Message.SmsgGmticketSystemstatus do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GMTICKET_SYSTEMSTATUS

  defstruct enabled?: true

  @impl ServerMessage
  def to_binary(%__MODULE__{enabled?: enabled?}), do: <<if(enabled?, do: 1, else: 0)::little-size(32)>>
end
