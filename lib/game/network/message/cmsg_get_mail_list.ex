defmodule ThistleTea.Game.Network.Message.CmsgGetMailList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GET_MAIL_LIST

  alias ThistleTea.Game.Player.Mail

  defstruct [:mailbox]

  @impl ClientMessage
  def handle(%__MODULE__{mailbox: mailbox}, state), do: Mail.list(state, mailbox)

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64)>>), do: %__MODULE__{mailbox: mailbox}
end
