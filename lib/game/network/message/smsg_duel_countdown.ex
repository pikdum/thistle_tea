defmodule ThistleTea.Game.Network.Message.SmsgDuelCountdown do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DUEL_COUNTDOWN

  defstruct [:time_ms]

  @impl ServerMessage
  def to_binary(%__MODULE__{time_ms: time_ms}) do
    <<time_ms::little-size(32)>>
  end
end
