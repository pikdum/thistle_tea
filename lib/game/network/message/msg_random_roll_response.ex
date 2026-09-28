defmodule ThistleTea.Game.Network.Message.MsgRandomRollResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_RANDOM_ROLL

  defstruct [:minimum, :maximum, :result, :guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{minimum: minimum, maximum: maximum, result: result, guid: guid}) do
    <<minimum::little-size(32), maximum::little-size(32), result::little-size(32), guid::little-size(64)>>
  end
end
