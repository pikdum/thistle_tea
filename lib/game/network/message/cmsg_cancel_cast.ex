defmodule ThistleTea.Game.Network.Message.CmsgCancelCast do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_CAST

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
