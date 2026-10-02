defmodule ThistleTea.Game.Network.Message.SmsgGmticketUpdatetext do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GMTICKET_UPDATETEXT

  defstruct [:response]

  @impl ServerMessage
  def to_binary(%__MODULE__{response: response}), do: <<response::little-size(32)>>
end
