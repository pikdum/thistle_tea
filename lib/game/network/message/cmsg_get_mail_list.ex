defmodule ThistleTea.Game.Network.Message.CmsgGetMailList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GET_MAIL_LIST

  defstruct [:mailbox]

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64)>>), do: %__MODULE__{mailbox: mailbox}
end
