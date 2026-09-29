defmodule ThistleTea.Game.World.Inbound.Mail do
  @moduledoc "Handles decoded mailbox client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Mail

  def messages do
    [
      Message.CmsgGetMailList,
      Message.CmsgItemTextQuery,
      Message.CmsgMailCreateTextItem,
      Message.CmsgMailDelete,
      Message.CmsgMailMarkAsRead,
      Message.CmsgMailReturnToSender,
      Message.CmsgMailTakeItem,
      Message.CmsgMailTakeMoney,
      Message.CmsgSendMail,
      Message.MsgQueryNextMailTimeClient
    ]
  end

  def handle(%Message.CmsgGetMailList{mailbox: mailbox}, state), do: Mail.list(state, mailbox)

  def handle(%Message.CmsgItemTextQuery{} = message, state), do: Mail.query_text(state, message)

  def handle(%Message.CmsgMailCreateTextItem{} = message, state), do: Mail.create_text_item(state, message)

  def handle(%Message.CmsgMailDelete{} = message, state), do: Mail.delete(state, message)

  def handle(%Message.CmsgMailMarkAsRead{} = message, state), do: Mail.mark_read(state, message)

  def handle(%Message.CmsgMailReturnToSender{} = message, state), do: Mail.return_to_sender(state, message)

  def handle(%Message.CmsgMailTakeItem{} = message, state), do: Mail.take_item(state, message)

  def handle(%Message.CmsgMailTakeMoney{} = message, state), do: Mail.take_money(state, message)

  def handle(%Message.CmsgSendMail{} = message, state), do: Mail.send_mail(state, message)

  def handle(%Message.MsgQueryNextMailTimeClient{}, state), do: Mail.query_next_time(state)
end
