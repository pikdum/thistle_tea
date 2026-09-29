defmodule ThistleTea.Game.Network.Message.CmsgPushquesttoparty do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PUSHQUESTTOPARTY

  defstruct [:quest_id]

  @impl ClientMessage
  def from_binary(<<quest_id::little-size(32)>>), do: %__MODULE__{quest_id: quest_id}
end
