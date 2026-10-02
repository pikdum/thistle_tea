defmodule ThistleTea.Game.Network.Message.SmsgGmticketGetticket do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GMTICKET_GETTICKET

  @has_text 0x06
  @default 0x0A

  defstruct [
    :message,
    :type,
    last_modified_age: 0.0,
    oldest_ticket_age: 0.0,
    estimated_wait_time: 0.0,
    escalation: 0,
    opened_by_gm: 0
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{message: nil}), do: <<@default::little-size(32)>>

  def to_binary(%__MODULE__{} = ticket) do
    <<@has_text::little-size(32), ticket.message::binary, 0, ticket.type::8,
      ticket.last_modified_age::little-float-size(32), ticket.oldest_ticket_age::little-float-size(32),
      ticket.estimated_wait_time::little-float-size(32), ticket.escalation::8, ticket.opened_by_gm::8>>
  end
end
