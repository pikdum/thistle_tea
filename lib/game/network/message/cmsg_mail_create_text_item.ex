defmodule ThistleTea.Game.Network.Message.CmsgMailCreateTextItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MAIL_CREATE_TEXT_ITEM

  alias ThistleTea.Game.Player.Mail

  defstruct [:mailbox, :mail_id, :mail_template_id]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Mail.create_text_item(state, message)

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64), mail_id::little-size(32), mail_template_id::little-size(32)>>),
    do: %__MODULE__{mailbox: mailbox, mail_id: mail_id, mail_template_id: mail_template_id}
end
