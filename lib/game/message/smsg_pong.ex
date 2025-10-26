defmodule ThistleTea.Game.Message.SmsgPong do
  use ThistleTea.Game.ServerMessage, :SMSG_PONG

  defstruct [:sequence_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{sequence_id: sequence_id}) do
    <<sequence_id::little-size(32)>>
  end
end
