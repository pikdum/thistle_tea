defmodule ThistleTea.Game.Inbound.Query do
  @moduledoc "Sends a cache query's response, when it has one, and leaves the state unchanged."

  alias ThistleTea.Game.World.Outbound

  def reply(nil, state), do: state

  def reply(response, state) do
    Outbound.send_packet(response)
    state
  end
end
