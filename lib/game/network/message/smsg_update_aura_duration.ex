defmodule ThistleTea.Game.Network.Message.SmsgUpdateAuraDuration do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_UPDATE_AURA_DURATION

  defstruct [:aura_slot, :duration_ms]

  @impl ServerMessage
  def to_binary(%__MODULE__{aura_slot: slot, duration_ms: duration}) do
    <<slot::little-size(8), duration::little-size(32)>>
  end
end
