defmodule ThistleTea.Game.Network.Message.CmsgMailMarkAsRead do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MAIL_MARK_AS_READ

  alias ThistleTea.Game.Player.Mail

  defstruct [:mailbox, :mail_id]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Mail.mark_read(state, message)

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64), mail_id::little-size(32)>>),
    do: %__MODULE__{mailbox: mailbox, mail_id: mail_id}
end
