defmodule ThistleTea.Game.Network.Message.SmsgGmticketDeleteticket do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GMTICKET_DELETETICKET

  defstruct [:response]

  @impl ServerMessage
  def to_binary(%__MODULE__{response: response}), do: <<response::little-size(32)>>
end
