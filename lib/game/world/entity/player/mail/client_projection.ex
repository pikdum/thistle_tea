defmodule ThistleTea.Game.World.Entity.Player.Mail.ClientProjection do
  @moduledoc """
  Projects semantic mailbox outcomes to the 1.12 mail protocol.
  """

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Outbound

  @actions %{
    send: 0,
    money_taken: 1,
    item_taken: 2,
    returned: 3,
    deleted: 4,
    made_permanent: 5
  }

  @results %{
    ok: 0,
    equip_error: 1,
    self: 2,
    not_enough_money: 3,
    recipient_not_found: 4,
    not_same_team: 5,
    internal: 6,
    attachment_invalid: 19
  }

  def received do
    Outbound.send_packet(%Message.SmsgReceivedMail{})
  end

  def list(mails, now) when is_list(mails) and is_integer(now) do
    Outbound.send_packet(%Message.SmsgMailListResult{mails: mails, now: now})
  end

  def text(item_text_id, text) when is_integer(item_text_id) and is_binary(text) do
    Outbound.send_packet(%Message.SmsgItemTextQueryResponse{item_text_id: item_text_id, text: text})
  end

  def next_delivery(unread_mails) when is_float(unread_mails) do
    Outbound.send_packet(%Message.MsgQueryNextMailTime{unread_mails: unread_mails})
  end

  def result(mail_id, action, result, opts \\ [])
      when is_integer(mail_id) and is_map_key(@actions, action) and is_map_key(@results, result) do
    Outbound.send_packet(%Message.SmsgSendMailResult{
      mail_id: mail_id,
      action: Map.fetch!(@actions, action),
      result: Map.fetch!(@results, result),
      equip_error: Keyword.get(opts, :equip_error, 0),
      item_entry: Keyword.get(opts, :item_entry, 0),
      item_count: Keyword.get(opts, :item_count, 0)
    })
  end
end
