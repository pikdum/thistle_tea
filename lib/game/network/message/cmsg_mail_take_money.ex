defmodule ThistleTea.Game.Network.Message.CmsgMailTakeMoney do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MAIL_TAKE_MONEY

  defstruct [:mailbox, :mail_id]

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64), mail_id::little-size(32)>>),
    do: %__MODULE__{mailbox: mailbox, mail_id: mail_id}
end
