defmodule ThistleTea.Game.Network do
  @moduledoc """
  The world-server wire layer: the ThousandIsland connection handler, header
  encryption, opcode tables, binary helpers, and one encoder module per server
  message. Framed client packets go to the `ThistleTea.Game.Network.Session`
  supplied at startup, which `ThistleTea.Game.Inbound` implements. Nothing
  here knows about the game world.
  """
  use Boundary, deps: [ThistleTea.Game.Core], exports: :all
end
