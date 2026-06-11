defmodule ThistleTea.Game.Network.Message.SmsgSpiritHealerConfirm do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPIRIT_HEALER_CONFIRM

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}) do
    <<guid::little-size(64)>>
  end
end
