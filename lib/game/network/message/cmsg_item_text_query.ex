defmodule ThistleTea.Game.Network.Message.CmsgItemTextQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ITEM_TEXT_QUERY

  alias ThistleTea.Game.Player.Mail

  defstruct [:item_text_id, :mail_id]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Mail.query_text(state, message)

  @impl ClientMessage
  def from_binary(<<item_text_id::little-size(32), mail_id::little-size(32), _unknown::little-size(32)>>),
    do: %__MODULE__{item_text_id: item_text_id, mail_id: mail_id}
end
