defmodule ThistleTea.Game.Inbound do
  @moduledoc """
  Client input. Each client message has one module here that decodes its
  payload and handles the decoded struct by calling into the world, the way
  a web layer sits on top of its domain: it depends on the network for wire
  helpers and on the world for the systems it drives, and nothing below
  depends on it.

  `ThistleTea.Game.Inbound.Session` connects the layer to the network
  listener, and every message implements `ThistleTea.Game.World.ClientInput`
  so a player process can apply it.
  """
  use Boundary,
    deps: [ThistleTea.Game.Core, ThistleTea.Game.Network, ThistleTea.Game.World, ThistleTea.Auth],
    exports: [Session]

  alias ThistleTea.Game.World.ClientInput

  defdelegate handle(message, state), to: ClientInput
end
