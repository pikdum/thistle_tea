defmodule ThistleTea.Game.Network.Message.SmsgPlaySound do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PLAY_SOUND

  defstruct [:sound_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{sound_id: sound_id}) do
    <<sound_id::little-size(32)>>
  end
end
