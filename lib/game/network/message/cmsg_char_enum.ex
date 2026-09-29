defmodule ThistleTea.Game.Network.Message.CmsgCharEnum do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHAR_ENUM

  alias ThistleTea.Game.Network.Message

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
