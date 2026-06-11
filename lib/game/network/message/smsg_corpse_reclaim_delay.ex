defmodule ThistleTea.Game.Network.Message.SmsgCorpseReclaimDelay do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CORPSE_RECLAIM_DELAY

  defstruct [:delay_ms]

  @impl ServerMessage
  def to_binary(%__MODULE__{delay_ms: delay_ms}) do
    <<delay_ms::little-size(32)>>
  end
end
