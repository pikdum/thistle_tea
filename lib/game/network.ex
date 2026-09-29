defmodule ThistleTea.Game.Network do
  @moduledoc """
  The world-server wire layer: the ThousandIsland connection handler, header
  encryption, opcode tables, and one codec module per client and server
  message. Client messages decode into structs and go to the
  `ThistleTea.Game.Network.Session` supplied at startup; server messages encode
  structs into packets. Nothing here knows about the game world.
  """
  use Boundary, deps: [ThistleTea.Game.Core], exports: :all
end
