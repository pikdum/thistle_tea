defmodule ThistleTea.Game.Network.Message.CmsgInspectHonorStats do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_INSPECT_HONOR_STATS

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
