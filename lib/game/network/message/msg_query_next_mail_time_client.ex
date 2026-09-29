defmodule ThistleTea.Game.Network.Message.MsgQueryNextMailTimeClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_QUERY_NEXT_MAIL_TIME

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
