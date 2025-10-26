defmodule ThistleTea.Game.Message.SmsgSetRestStart do
  use ThistleTea.Game.ServerMessage, :SMSG_SET_REST_START

  defstruct [:unknown1]

  @impl ServerMessage
  def to_binary(%__MODULE__{unknown1: unknown1}) do
    <<unknown1::little-size(32)>>
  end
end
