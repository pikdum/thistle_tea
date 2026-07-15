defmodule ThistleTea.Game.Network.Message.SmsgReceivedMail do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_RECEIVED_MAIL

  defstruct delay: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{delay: delay}), do: <<delay::little-size(32)>>
end
