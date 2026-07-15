defmodule ThistleTea.Game.Network.Message.SmsgSendMailResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SEND_MAIL_RESULT

  defstruct mail_id: 0, action: 0, result: 0, equip_error: 0, item_entry: 0, item_count: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{action: 2} = message) do
    base = <<message.mail_id::little-size(32), message.action::little-size(32), message.result::little-size(32)>>

    if message.result == 1 do
      base <> <<message.equip_error::little-size(32)>>
    else
      base <> <<message.item_entry::little-size(32), message.item_count::little-size(32)>>
    end
  end

  def to_binary(%__MODULE__{} = message) do
    base = <<message.mail_id::little-size(32), message.action::little-size(32), message.result::little-size(32)>>
    if message.result == 1, do: base <> <<message.equip_error::little-size(32)>>, else: base
  end
end
