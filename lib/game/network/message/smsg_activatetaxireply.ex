defmodule ThistleTea.Game.Network.Message.SmsgActivatetaxireply do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ACTIVATETAXIREPLY

  defstruct [:reply]

  @impl ServerMessage
  def to_binary(%__MODULE__{reply: reply}), do: <<reply::little-size(32)>>
end
