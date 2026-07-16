defmodule ThistleTea.Game.Network.Message.SmsgInstanceResetFailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INSTANCE_RESET_FAILED

  defstruct [:reason, :map]

  @impl ServerMessage
  def to_binary(%__MODULE__{reason: reason, map: map}) do
    <<reason::little-size(32), map::little-size(32)>>
  end
end
