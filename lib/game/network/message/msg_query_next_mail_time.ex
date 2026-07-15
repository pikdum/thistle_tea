defmodule ThistleTea.Game.Network.Message.MsgQueryNextMailTime do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_QUERY_NEXT_MAIL_TIME

  defstruct unread_mails: -1.0

  @impl ServerMessage
  def to_binary(%__MODULE__{unread_mails: unread_mails}), do: <<unread_mails::little-float-size(32)>>
end
