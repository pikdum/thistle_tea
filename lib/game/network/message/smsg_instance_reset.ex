defmodule ThistleTea.Game.Network.Message.SmsgInstanceReset do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INSTANCE_RESET

  defstruct [:map]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map}) do
    <<map::little-size(32)>>
  end
end
