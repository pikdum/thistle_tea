defmodule ThistleTea.Game.Network.Message.SmsgCharDelete do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CHAR_DELETE

  @result %{
    success: 0x39,
    failed: 0x3A
  }

  def result(key), do: Map.fetch!(@result, key)

  defstruct [:result]

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}) do
    <<result::little-size(8)>>
  end
end
