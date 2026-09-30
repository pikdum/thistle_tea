defmodule ThistleTea.Game.Inbound.CmsgMailDelete do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_MAIL_DELETE

  alias ThistleTea.Game.World.Entity.Player.Mail

  defstruct [:mailbox, :mail_id]

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64), mail_id::little-size(32)>>),
    do: %__MODULE__{mailbox: mailbox, mail_id: mail_id}

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Mail.delete(state, message)
end
