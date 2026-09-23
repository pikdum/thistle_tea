defmodule ThistleTea.Game.Network.Message.SmsgInstanceSaveCreated do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INSTANCE_SAVE_CREATED

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<0::little-size(32)>>
end
