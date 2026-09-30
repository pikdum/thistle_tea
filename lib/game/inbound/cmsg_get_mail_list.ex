defmodule ThistleTea.Game.Inbound.CmsgGetMailList do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GET_MAIL_LIST

  alias ThistleTea.Game.World.Entity.Player.Mail

  defstruct [:mailbox]

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64)>>), do: %__MODULE__{mailbox: mailbox}

  @impl ClientMessage
  def handle(%__MODULE__{mailbox: mailbox}, state), do: Mail.list(state, mailbox)
end
