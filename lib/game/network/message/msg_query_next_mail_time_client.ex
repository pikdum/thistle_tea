defmodule ThistleTea.Game.Network.Message.MsgQueryNextMailTimeClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_QUERY_NEXT_MAIL_TIME

  alias ThistleTea.Game.Player.Mail

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Mail.query_next_time(state)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
