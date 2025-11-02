defmodule ThistleTea.Game.Network.Message.SmsgAuthChallenge do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUTH_CHALLENGE

  defstruct [:server_seed]

  @impl ServerMessage
  def to_binary(%__MODULE__{server_seed: server_seed}) do
    <<server_seed::little-size(32)>>
  end
end
