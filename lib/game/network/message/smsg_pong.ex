defmodule ThistleTea.Game.Network.Message.SmsgPong do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PONG

  defstruct [:sequence_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{sequence_id: sequence_id}) do
    <<sequence_id::little-size(32)>>
  end
end
