defmodule ThistleTea.Game.Network.Message.SmsgCharCreate do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CHAR_CREATE

  @result %{
    success: 0x2E,
    error: 0x2F,
    failed: 0x30,
    name_in_use: 0x31
  }

  def result, do: @result
  def result(key), do: Map.fetch!(@result, key)

  defstruct [:result]

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}) do
    <<result::little-size(8)>>
  end
end
