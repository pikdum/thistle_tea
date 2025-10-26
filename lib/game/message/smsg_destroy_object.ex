defmodule ThistleTea.Game.Message.SmsgDestroyObject do
  use ThistleTea.Game.ServerMessage, :SMSG_DESTROY_OBJECT

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}) do
    <<guid::little-size(64)>>
  end
end
