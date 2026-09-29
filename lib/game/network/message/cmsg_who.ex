defmodule ThistleTea.Game.Network.Message.CmsgWho do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_WHO

  alias ThistleTea.Game.Network.Message

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
