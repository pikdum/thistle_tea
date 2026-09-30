defmodule ThistleTea.Game.Inbound.MsgQueryNextMailTimeClient do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_QUERY_NEXT_MAIL_TIME

  alias ThistleTea.Game.World.Entity.Player.Mail

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Mail.query_next_time(state)
end
