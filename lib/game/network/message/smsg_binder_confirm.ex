defmodule ThistleTea.Game.Network.Message.SmsgBinderConfirm do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BINDER_CONFIRM

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
