defmodule ThistleTea.Game.Network.Message.SmsgStableResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_STABLE_RESULT

  defstruct [:result]

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}), do: <<result::little-size(8)>>
end
