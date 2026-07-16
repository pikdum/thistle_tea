defmodule ThistleTea.Game.Network.Message.SmsgAreaTriggerMessage do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AREA_TRIGGER_MESSAGE

  defstruct [:message]

  @impl ServerMessage
  def to_binary(%__MODULE__{message: message}) when is_binary(message) do
    <<byte_size(message) + 1::little-size(32)>> <> message <> <<0>>
  end
end
