defmodule ThistleTea.Game.Network.Message.SmsgDefenseMessage do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DEFENSE_MESSAGE

  defstruct [:zone_id, :text]

  @impl ServerMessage
  def to_binary(%__MODULE__{zone_id: zone_id, text: text}) do
    <<zone_id::little-size(32), byte_size(text) + 1::little-size(32), text::binary, 0>>
  end
end
