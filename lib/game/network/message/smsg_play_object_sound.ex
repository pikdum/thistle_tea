defmodule ThistleTea.Game.Network.Message.SmsgPlayObjectSound do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PLAY_OBJECT_SOUND

  defstruct [:sound_id, :guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{sound_id: sound_id, guid: guid}) do
    <<sound_id::little-size(32), guid::little-size(64)>>
  end
end
