defmodule ThistleTea.Game.Network.Message.CmsgMailTakeItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MAIL_TAKE_ITEM

  alias ThistleTea.Game.Player.Mail

  defstruct [:mailbox, :mail_id]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Mail.take_item(state, message)

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64), mail_id::little-size(32)>>),
    do: %__MODULE__{mailbox: mailbox, mail_id: mail_id}
end
